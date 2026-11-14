package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * #21–#23 黑名单：一条单向关系——只断「被拉黑方 → 拉黑方」，
 * 拉黑不解除好友关系、群聊不拦、只有真人能做（docs/truth/backend/friendship.md）。
 */
class BlocklistApiTest extends ApiTestSupport {

    @Test
    void 拉黑后出现在我的列表里且带名字与时间() throws Exception {
        Caller me = newCaller();
        Caller target = newCaller();

        mockMvc.perform(get("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0))
                .andExpect(jsonPath("$.page").value(1))
                .andExpect(jsonPath("$.size").value(50))
                .andExpect(jsonPath("$.total").value(0));

        block(me, target.accountId())
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.account_id").value(target.accountId()))
                .andExpect(jsonPath("$.display_name").value("路人"))
                .andExpect(jsonPath("$.created_at").exists());

        mockMvc.perform(get("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].account_id").value(target.accountId()))
                .andExpect(jsonPath("$.items[0].display_name").value("路人"))
                .andExpect(jsonPath("$.total").value(1));
    }

    @Test
    void 翻页不重复不漏行且total是总数() throws Exception {
        Caller me = newCaller();
        for (int i = 0; i < 3; i++) {
            block(me, newCaller().accountId()).andExpect(status().isCreated());
        }

        // 三条同秒写入：靠 blocked_account_id 做 tiebreaker，两页不能重叠也不能漏
        List<Long> firstPage = ids(getPage(me, 1, 2), 2);
        List<Long> secondPage = ids(getPage(me, 2, 2), 1);
        assertThat(firstPage).doesNotContainAnyElementsOf(secondPage);

        mockMvc.perform(get("/api/blocklist?page=2&size=2")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(jsonPath("$.page").value(2))
                .andExpect(jsonPath("$.size").value(2))
                .andExpect(jsonPath("$.total").value(3));
    }

    @Test
    void page与size非法都是校验失败() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(get("/api/blocklist?page=0")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("page"));
        mockMvc.perform(get("/api/blocklist?size=0")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("size"));
        mockMvc.perform(get("/api/blocklist?size=101")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("size"));
    }

    @Test
    void 满一百人后回blocklist_full而不是conflict() throws Exception {
        Caller me = newCaller();
        Caller target = newCaller();
        // 直接铺满 99 行，只剩一个名额：不为一千次 REST 调用付时间
        for (int i = 0; i < 99; i++) {
            jdbc.update("insert into blocklist (owner_account_id, blocked_account_id) values (?, ?)",
                    me.accountId(), 900000L + i);
        }
        block(me, target.accountId()).andExpect(status().isCreated());

        Caller another = newCaller();
        block(me, another.accountId())
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("blocklist_full"));
        assertThat(jdbc.queryForObject("select count(*) from blocklist where owner_account_id = ?",
                Long.class, me.accountId())).isEqualTo(100);
    }

    @Test
    void 被拉黑方不能私聊也不能申请好友但拉黑方都能() throws Exception {
        Caller blocker = newCaller();
        Caller blocked = newCaller();
        befriend(blocker, blocked);
        block(blocker, blocked.accountId()).andExpect(status().isCreated());

        // 被拉黑方 → 拉黑方：两个入口都被拦，而且拿的是 blocked 而不是 not_friend
        mockMvc.perform(post("/api/conversations/dm/" + blocker.accountId() + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(blocked.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"在吗"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("blocked"));
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(blocked.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(blocker.accountId())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("blocked"));

        // 反方向不拦：拉黑方主动私聊仍然成立（拉黑不解除好友关系）
        mockMvc.perform(post("/api/conversations/dm/" + blocked.accountId() + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(blocker.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"我先说"}
                                """))
                .andExpect(status().isCreated());
    }

    @Test
    void 拉黑不解除好友关系且群聊两个方向都不拦() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        befriend(owner, member);
        long roomId = createRoom(owner);
        addMember(owner, roomId, member.accountId());

        block(member, owner.accountId()).andExpect(status().isCreated());

        // 好友行原样保留：拉黑不动 friendship，取消拉黑后关系照旧
        assertThat(jdbc.queryForObject("""
                select count(*) from friendship where account_id = ? and peer_account_id = ?
                    and status = 'accepted' and deleted_at is null
                """, Long.class, Math.min(owner.accountId(), member.accountId()),
                Math.max(owner.accountId(), member.accountId()))).isEqualTo(1);

        // 群聊是另一条授权，不因一对一的拉黑被弄断
        mockMvc.perform(post("/api/conversations/room/" + roomId + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"群里说"}
                                """))
                .andExpect(status().isCreated());

        // 取消拉黑后私聊恢复
        mockMvc.perform(delete("/api/blocklist/" + owner.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(post("/api/conversations/dm/" + owner.accountId() + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"又能发了"}
                                """))
                .andExpect(status().isCreated());
    }

    @Test
    void 重复拉黑是冲突而取消不存在的返回未找到() throws Exception {
        Caller me = newCaller();
        Caller target = newCaller();

        block(me, target.accountId()).andExpect(status().isCreated());
        block(me, target.accountId())
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("conflict"));

        mockMvc.perform(delete("/api/blocklist/" + target.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/blocklist/" + target.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
        assertThat(jdbc.queryForObject("select count(*) from blocklist where owner_account_id = ?",
                Long.class, me.accountId())).isZero();
    }

    @Test
    void 拉黑自己不存在的账号与冻结各有自己的码() throws Exception {
        Caller me = newCaller();

        block(me, me.accountId())
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("account_id"));
        block(me, 99999999)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));

        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());
        block(me, newCaller().accountId())
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
    }

    @Test
    void agent能看自己的黑名单但不能拉黑也不能取消() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        Caller target = newCaller();

        mockMvc.perform(get("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));

        mockMvc.perform(post("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(target.accountId())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));

        mockMvc.perform(delete("/api/blocklist/" + target.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
    }

    @Test
    void 拉黑方向不同就是两行() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        block(a, b.accountId()).andExpect(status().isCreated());
        block(b, a.accountId()).andExpect(status().isCreated());

        assertThat(jdbc.queryForObject("""
                select count(*) from blocklist
                where (owner_account_id = ? and blocked_account_id = ?)
                   or (owner_account_id = ? and blocked_account_id = ?)
                """, Long.class, a.accountId(), b.accountId(), b.accountId(), a.accountId())).isEqualTo(2);
        assertThat(jdbc.queryForObject("""
                select count(*) from blocklist where owner_account_id = ? and blocked_account_id = ?
                """, Long.class, a.accountId(), b.accountId())).isEqualTo(1);
    }

    @Test
    void 并发重复拉黑不会出现服务端错误() throws Exception {
        Caller me = newCaller();
        Caller target = newCaller();

        List<Integer> codes = racePost("/api/blocklist", me.token(), """
                {"account_id":%d}
                """.formatted(target.accountId()));

        assertThat(codes).allMatch(code -> code == 201 || code == 409).contains(201);
        assertThat(jdbc.queryForObject("select count(*) from blocklist where owner_account_id = ?",
                Long.class, me.accountId())).isEqualTo(1);
    }

    private String getPage(Caller me, int page, int size) throws Exception {
        return mockMvc.perform(get("/api/blocklist?page=" + page + "&size=" + size)
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    private List<Long> ids(String body, int expected) {
        List<Number> raw = JsonPath.read(body, "$.items[*].account_id");
        assertThat(raw).hasSize(expected);
        return raw.stream().map(Number::longValue).toList();
    }

    private org.springframework.test.web.servlet.ResultActions block(Caller me, long accountId) throws Exception {
        return mockMvc.perform(post("/api/blocklist")
                .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"account_id":%d}
                        """.formatted(accountId)));
    }

    private void befriend(Caller one, Caller another) throws Exception {
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(one.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(another.accountId())))
                .andExpect(status().isCreated());
        mockMvc.perform(post("/api/friendships/" + one.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(another.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isOk());
    }

    private long createRoom(Caller owner) throws Exception {
        String body = mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"读书会"}
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return ((Number) JsonPath.read(body, "$.room_id")).longValue();
    }

    private void addMember(Caller actor, long roomId, long accountId) throws Exception {
        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(actor.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(accountId)))
                .andExpect(status().isCreated());
    }
}
