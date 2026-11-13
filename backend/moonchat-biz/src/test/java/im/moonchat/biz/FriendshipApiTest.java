package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/** #8–#11 好友四条：申请 → 同意 → 双方列表出现；拒绝与删除都是 tombstone，复用原行。 */
class FriendshipApiTest extends ApiTestSupport {

    @Test
    void 申请后出现在对方待处理里而我的待处理是空的() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(b.accountId())))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.peer_account_id").value(b.accountId()))
                .andExpect(jsonPath("$.status").value("pending"))
                .andExpect(jsonPath("$.incoming").value(false));

        mockMvc.perform(get("/api/friendships?status=pending")
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].peer_account_id").value(a.accountId()))
                .andExpect(jsonPath("$.items[0].display_name").value("路人"))
                .andExpect(jsonPath("$.items[0].incoming").value(true));

        mockMvc.perform(get("/api/friendships?status=pending")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
    }

    @Test
    void 同意后双方好友列表都出现且资料页变成已是好友() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());

        mockMvc.perform(post("/api/friendships/" + a.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.peer_account_id").value(a.accountId()))
                .andExpect(jsonPath("$.status").value("accepted"));

        for (Caller side : new Caller[] {a, b}) {
            long peer = side == a ? b.accountId() : a.accountId();
            mockMvc.perform(get("/api/friendships")
                            .header(HttpHeaders.AUTHORIZATION, bearer(side.token())))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.items.length()").value(1))
                    .andExpect(jsonPath("$.items[0].peer_account_id").value(peer))
                    .andExpect(jsonPath("$.items[0].status").value("accepted"))
                    .andExpect(jsonPath("$.items[0].incoming").value(false));
        }

        mockMvc.perform(get("/api/accounts/" + b.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token())))
                .andExpect(jsonPath("$.is_friend").value(true));
    }

    @Test
    void 两张表同事务双写且小id在前() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());
        // 另一对由 id 较大的一方发起，规范序不能由「谁先申请」决定
        Caller c = newCaller();
        requestFriend(c, a.accountId());

        Map<String, Object> forward = jdbc.queryForMap("""
                select account_id, peer_account_id, status, requested_by, id
                from friendship where peer_account_id = ?
                """, b.accountId());
        assertThat(((Number) forward.get("account_id")).longValue())
                .isEqualTo(Math.min(a.accountId(), b.accountId()));
        assertThat(((Number) forward.get("peer_account_id")).longValue())
                .isEqualTo(Math.max(a.accountId(), b.accountId()));
        assertThat(forward.get("status")).isEqualTo("pending");
        assertThat(((Number) forward.get("requested_by")).longValue()).isEqualTo(a.accountId());

        Map<String, Object> reverse = jdbc.queryForMap("""
                select account_id, peer_account_id, friendship_id, status, requested_by
                from friendship_reverse where account_id = ? and peer_account_id = ?
                """, Math.max(a.accountId(), b.accountId()), Math.min(a.accountId(), b.accountId()));
        assertThat(((Number) reverse.get("account_id")).longValue())
                .isEqualTo(Math.max(a.accountId(), b.accountId()));
        assertThat(((Number) reverse.get("friendship_id")).longValue())
                .isEqualTo(((Number) forward.get("id")).longValue());
        assertThat(reverse.get("status")).isEqualTo("pending");
        assertThat(((Number) reverse.get("requested_by")).longValue()).isEqualTo(a.accountId());

        Map<String, Object> fromLargerId = jdbc.queryForMap("""
                select account_id, peer_account_id, requested_by from friendship
                where account_id = ? and peer_account_id = ?
                """, Math.min(a.accountId(), c.accountId()), Math.max(a.accountId(), c.accountId()));
        assertThat(((Number) fromLargerId.get("requested_by")).longValue()).isEqualTo(c.accountId());
    }

    @Test
    void 拒绝只写tombstone且再申请复用原行() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());

        mockMvc.perform(post("/api/friendships/" + a.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"reject"}
                                """))
                .andExpect(status().isNoContent());

        assertThat(jdbc.queryForMap("select status, deleted_at from friendship where peer_account_id = ?",
                Math.max(a.accountId(), b.accountId())).get("status"))
                .isEqualTo("pending");
        assertThat(jdbc.queryForObject("select count(*) from friendship where deleted_at is not null", Long.class))
                .isPositive();
        assertThat(jdbc.queryForObject("""
                select count(*) from friendship_reverse where deleted_at is not null and friendship_id = (
                    select id from friendship where peer_account_id = ?)
                """, Long.class, Math.max(a.accountId(), b.accountId())))
                .isEqualTo(1);

        mockMvc.perform(get("/api/friendships?status=pending")
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token())))
                .andExpect(jsonPath("$.items.length()").value(0));

        // 被拒之后由被申请方重新发起：复用同一行，不插入第二个同 pair 行
        Timestamp rejectedAt = jdbc.queryForObject("select updated_at from friendship where peer_account_id = ?",
                Timestamp.class, Math.max(a.accountId(), b.accountId()));
        requestFriend(b, a.accountId());

        Map<String, Object> reused = jdbc.queryForMap("""
                select count(*) over () as rows, status, requested_by, deleted_at, created_at
                from friendship where peer_account_id = ?
                """, Math.max(a.accountId(), b.accountId()));
        assertThat(((Number) reused.get("rows")).intValue()).isEqualTo(1);
        assertThat(reused.get("status")).isEqualTo("pending");
        assertThat(reused.get("deleted_at")).isNull();
        assertThat(((Number) reused.get("requested_by")).longValue()).isEqualTo(b.accountId());
        assertThat(((Timestamp) reused.get("created_at")).after(rejectedAt)).isTrue();
    }

    @Test
    void 删好友后返回未找到且再申请复用原行() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());
        acceptFriend(b, a.accountId());

        mockMvc.perform(delete("/api/friendships/" + b.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/friendships/" + b.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));

        mockMvc.perform(get("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token())))
                .andExpect(jsonPath("$.items.length()").value(0));
        assertThat(jdbc.queryForObject("select count(*) from friendship_reverse where deleted_at is not null",
                Long.class)).isPositive();

        requestFriend(a, b.accountId());
        assertThat(jdbc.queryForObject("select count(*) from friendship where peer_account_id = ?",
                Long.class, Math.max(a.accountId(), b.accountId())))
                .isEqualTo(1);
        assertThat(jdbc.queryForObject("select deleted_at from friendship where peer_account_id = ?",
                Timestamp.class, Math.max(a.accountId(), b.accountId())))
                .isNull();
    }

    @Test
    void 已是好友或已有待处理申请都是冲突() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(b.accountId())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("conflict"));

        acceptFriend(b, a.accountId());
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(a.accountId())))
                .andExpect(status().isConflict());
    }

    @Test
    void 申请自己的与不存在的账号各有自己的码() throws Exception {
        Caller a = newCaller();

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(a.accountId())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("peer_account_id"));

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":99999999}
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
    }

    @Test
    void 冻结的任一方都不能申请也不能应答() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());

        jdbc.update("update account_info set status = 'frozen' where account_id = ?", b.accountId());
        mockMvc.perform(post("/api/friendships/" + a.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));

        Caller c = newCaller();
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(b.accountId())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(c.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(b.accountId())))
                .andExpect(status().isForbidden());
    }

    @Test
    void 自己发出去的申请不能自己应答() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();
        requestFriend(a, b.accountId());

        mockMvc.perform(post("/api/friendships/" + b.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
    }

    @Test
    void 没有待处理申请时应答返回未找到且action非法是校验失败() throws Exception {
        Caller a = newCaller();
        Caller b = newCaller();

        mockMvc.perform(post("/api/friendships/" + b.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));

        requestFriend(a, b.accountId());
        mockMvc.perform(post("/api/friendships/" + a.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"同意"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("action"));
    }

    @Test
    void status不在枚举内是校验失败() throws Exception {
        Caller a = newCaller();

        mockMvc.perform(get("/api/friendships?status=blocked")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("status"));
    }

    @Test
    void agent用密钥能发好友申请也能看自己的列表() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        Caller peer = newCaller();

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(peer.accountId())))
                .andExpect(status().isCreated());

        mockMvc.perform(get("/api/friendships?status=pending")
                        .header(HttpHeaders.AUTHORIZATION, bearer(peer.token())))
                .andExpect(jsonPath("$.items[0].peer_account_id").value(agent.accountId()))
                .andExpect(jsonPath("$.items[0].display_name").value("小助手"));
    }

    /**
     * 两个并发申请可能都读到「无行」：`friendship_pair_uq` 兜底，落败方拿 409，而不是 500。
     * 窗口约 1ms，不保证每次都撞上，所以断言只写「不落在 5xx」与「最终只有一行」。
     */
    @Test
    void 并发申请同一个人不会出现服务端错误() throws Exception {
        Caller from = newCaller();
        Caller peer = newCaller();

        List<Integer> codes = racePost("/api/friendships", from.token(), """
                {"peer_account_id":%d}
                """.formatted(peer.accountId()));

        assertThat(codes).allMatch(code -> code == 201 || code == 409).contains(201);
        assertThat(jdbc.queryForObject("""
                select count(*) from friendship
                where account_id = ? and peer_account_id = ? and deleted_at is null
                """, Long.class, Math.min(from.accountId(), peer.accountId()),
                Math.max(from.accountId(), peer.accountId()))).isEqualTo(1);
    }

    private void requestFriend(Caller from, long peerAccountId) throws Exception {
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(from.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(peerAccountId)))
                .andExpect(status().isCreated());
    }

    private void acceptFriend(Caller answerer, long requesterAccountId) throws Exception {
        mockMvc.perform(post("/api/friendships/" + requesterAccountId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(answerer.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isOk());
    }
}
