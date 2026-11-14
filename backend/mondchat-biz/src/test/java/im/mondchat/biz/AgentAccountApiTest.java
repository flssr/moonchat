package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

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
