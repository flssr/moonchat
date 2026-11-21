package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/**
 * #37 已读上报：只写本人的读游标。两条最容易写错的事实在这里被钉死——
 * 群侧键用 `room_info.turms_group_id`（不是 `room_id`），私聊键的 owner 是调用者自己（不是路径里的对端）。
 * 都写错时 Turms 不报错、客户端角标永远不清，所以只能靠断言 Admin 收到的 query 形状来兜。
 */
class ReadMarkerApiTest extends ApiTestSupport {

    @Test
    void 成员标群会话回204且键用Turms群id落到自己身上() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner);
        addMember(owner, roomId, member.accountId());
        long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);

        markRead(member.token(), "room", roomId)
                .andExpect(status().isNoContent());

        assertThat(TestStack.TURMS_ADMIN.lastMethod()).isEqualTo("PUT");
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isEqualTo("/conversations");
        String query = TestStack.TURMS_ADMIN.lastQuery();
        assertThat(query).contains("groupConversationMemberKeys");
        assertThat(query).contains("groupId=" + turmsGroupId);
        assertThat(query).contains("memberId=" + member.accountId());
        // readDate 传 null：时间由 Turms 按服务端此刻取
        assertThat(TestStack.TURMS_ADMIN.lastBody()).contains("\"readDate\"");
        assertThat(JsonPath.<Object>read(TestStack.TURMS_ADMIN.lastBody(), "$.readDate")).isNull();
    }

    @Test
    void 同一会话连调两次都是204() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);

        markRead(me.token(), "dm", peer.accountId()).andExpect(status().isNoContent());
        markRead(me.token(), "dm", peer.accountId()).andExpect(status().isNoContent());
    }

    @Test
    void 非成员标群会话回403且根本没碰Turms() throws Exception {
        Caller owner = newCaller();
        Caller stranger = newCaller();
        long roomId = createRoom(owner);

        markRead(stranger.token(), "room", roomId)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isNotEqualTo("/conversations");
    }

    @Test
    void 群还没有Turms群id时回503() throws Exception {
        Caller owner = newCaller();
        long roomId = createRoom(owner);
        jdbc.update("update room_info set turms_group_id = null, turms_sync_state = 'pending' where id = ?", roomId);

        markRead(owner.token(), "room", roomId)
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isNotEqualTo("/conversations");
    }

    @Test
    void 私聊的owner是调用者自己所以不影响对端() throws Exception {
        Caller alice = newCaller();
        Caller bob = newCaller();
        befriend(alice, bob);

        markRead(alice.token(), "dm", bob.accountId()).andExpect(status().isNoContent());
        String aliceQuery = TestStack.TURMS_ADMIN.lastQuery();
        assertThat(aliceQuery).contains("privateConversationKeys");
        assertThat(aliceQuery).contains("ownerId=" + alice.accountId());
        assertThat(aliceQuery).contains("targetId=" + bob.accountId());

        // bob 标已读写的是 bob 自己的游标，不是 alice 的
        markRead(bob.token(), "dm", alice.accountId()).andExpect(status().isNoContent());
        String bobQuery = TestStack.TURMS_ADMIN.lastQuery();
        assertThat(bobQuery).contains("ownerId=" + bob.accountId());
        assertThat(bobQuery).contains("targetId=" + alice.accountId());
    }

    @Test
    void 删好友后仍能标已读() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);
        mockMvc.perform(delete("/api/friendships/" + peer.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isNoContent());

        // 会话保留只读，角标还要能清：不校验好友关系
        markRead(me.token(), "dm", peer.accountId()).andExpect(status().isNoContent());
    }

    @Test
    void 冻结账号也能标已读() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        // 已读只改自己的读游标，不属于「冻结停写」：拒绝会让角标永久挂着
        markRead(me.token(), "dm", peer.accountId()).andExpect(status().isNoContent());
    }

    @Test
    void 会话解析的两条错误各有自己的码() throws Exception {
        Caller me = newCaller();

        markRead(me.token(), "dm", 99999999)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
        markRead(me.token(), "dm", me.accountId())
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("id"));
        markRead(me.token(), "room", 99999999)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
        markRead(me.token(), "channel", 1)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("type"));
    }

    @Test
    void Turms没确认时回503() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);

        TestStack.TURMS_ADMIN.respondWith(500);
        markRead(me.token(), "dm", peer.accountId())
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));
    }

    private ResultActions markRead(String credential, String type, long id) throws Exception {
        return mockMvc.perform(post("/api/conversations/" + type + "/" + id + "/read")
                .header(HttpHeaders.AUTHORIZATION, bearer(credential)));
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
