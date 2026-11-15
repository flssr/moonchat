package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/** #5 建 agent 账号：两行同事务、一次性明文密钥、agent 建不了 agent。 */
class AgentAccountApiTest extends ApiTestSupport {

    @Test
    void 建agent返回一次性密钥并把两行写齐() throws Exception {
        Caller me = newCaller();

        String body = mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"小助手"}
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.display_name").value("小助手"))
                .andReturn().getResponse().getContentAsString();

        long agentId = ((Number) JsonPath.read(body, "$.account_id")).longValue();
        String accountKey = JsonPath.read(body, "$.account_key");
        assertThat(accountKey)
                .matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

        assertThat(jdbc.queryForObject("select type from account where id = ?", String.class, agentId))
                .isEqualTo("agent");
        assertThat(jdbc.queryForObject("select owner_account_id from account where id = ?", Long.class, agentId))
                .isEqualTo(me.accountId());
        assertThat(jdbc.queryForObject("select turms_sync_state from account where id = ?", String.class, agentId))
                .isEqualTo("synced");
        assertThat(jdbc.queryForObject("select email from account_info where account_id = ?", String.class, agentId))
                .isNull();
        assertThat(jdbc.queryForObject("select credential_hash from account_info where account_id = ?",
                String.class, agentId))
                .startsWith("hmac-sha256$")
                .doesNotContain(accountKey);
    }

    @Test
    void 建agent按同一个id建Turms用户() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "阿助");

        assertThat(TestStack.TURMS_ADMIN.lastPath()).isEqualTo("/users");
        String turmsUser = TestStack.TURMS_ADMIN.lastBody();
        assertThat(((Number) JsonPath.read(turmsUser, "$.id")).longValue()).isEqualTo(agent.accountId());
        assertThat(JsonPath.read(turmsUser, "$.name").toString()).isEqualTo("阿助");
    }

    @Test
    void agent建不了agent() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"套娃"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));

        assertThat(jdbc.queryForObject("select count(*) from account where owner_account_id = ?", Long.class,
                agent.accountId()))
                .isZero();
    }

    @Test
    void 建Turms用户失败时连账号行一起回滚() throws Exception {
        Caller me = newCaller();
        TestStack.TURMS_ADMIN.respondWith(500);

        mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"孤儿"}
                                """))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));

        assertThat(jdbc.queryForObject("select count(*) from account where owner_account_id = ?", Long.class,
                me.accountId()))
                .isZero();
        // 好友两行也在同一事务里：建用户失败不留「半截好友关系」
        assertThat(jdbc.queryForObject("""
                select count(*) from friendship where account_id = ? or peer_account_id = ?
                """, Long.class, me.accountId(), me.accountId())).isZero();
    }

    @Test
    void 建完agent双方立刻互为好友() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        // 归属者侧看得见新 agent，状态已是 accepted、且不是「发给我的待处理」
        mockMvc.perform(get("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].peer_account_id").value(agent.accountId()))
                .andExpect(jsonPath("$.items[0].status").value("accepted"))
                .andExpect(jsonPath("$.items[0].incoming").value(false));

        // agent 用密钥看自己那一侧
        mockMvc.perform(get("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].peer_account_id").value(me.accountId()));

        mockMvc.perform(get("/api/accounts/" + agent.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(jsonPath("$.is_friend").value(true));

        // 一对账号两行：主表记 requested_by = 归属者，镜像按 friendship_id 指回主表
        long lower = Math.min(me.accountId(), agent.accountId());
        long higher = Math.max(me.accountId(), agent.accountId());
        assertThat(jdbc.queryForObject("""
                select requested_by from friendship
                where account_id = ? and peer_account_id = ? and status = 'accepted' and deleted_at is null
                """, Long.class, lower, higher)).isEqualTo(me.accountId());
        assertThat(jdbc.queryForObject("""
                select count(*) from friendship_reverse where account_id = ? and peer_account_id = ?
                    and friendship_id = (select id from friendship where account_id = ? and peer_account_id = ?)
                """, Long.class, higher, lower, lower, higher)).isEqualTo(1);
    }

    @Test
    void 建完agent后双方不用加好友就能私聊() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        assertThat(sendDm(me.token(), agent.accountId(), "你好").andReturn().getResponse().getStatus())
                .isEqualTo(201);
        assertThat(sendDm(agent.accountKey(), me.accountId(), "在").andReturn().getResponse().getStatus())
                .isEqualTo(201);
    }

    @Test
    void 删掉这层好友关系后不会自动重建() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        mockMvc.perform(delete("/api/friendships/" + agent.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(jsonPath("$.items.length()").value(0));
        // 删除写 tombstone，不会因为「归属关系还在」再插一行
        assertThat(jdbc.queryForObject("select count(*) from friendship where account_id = ? and peer_account_id = ?",
                Long.class, Math.min(me.accountId(), agent.accountId()),
                Math.max(me.accountId(), agent.accountId()))).isEqualTo(1);
        assertThat(jdbc.queryForObject("select deleted_at from friendship where account_id = ? and peer_account_id = ?",
                java.sql.Timestamp.class, Math.min(me.accountId(), agent.accountId()),
                Math.max(me.accountId(), agent.accountId()))).isNotNull();
    }

    /** 建 agent 后不用手工加好友就能发私聊：直接打写入网关的 dm 分支。 */
    private ResultActions sendDm(String credential, long peerAccountId, String text) throws Exception {
        return mockMvc.perform(post("/api/conversations/dm/" + peerAccountId + "/messages")
                .header(HttpHeaders.AUTHORIZATION, bearer(credential))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"text":"%s"}
                        """.formatted(text)));
    }

    @Test
    void 名字校验与缺凭据() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"   "}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("display_name"));

        mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"%s"}
                                """.formatted("名".repeat(21))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("display_name"));

        mockMvc.perform(post("/api/agent-accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"没凭据"}
                                """))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }
}
