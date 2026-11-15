package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/**
 * #19 写入网关：两条授权拒绝、被移出群后立即被拒、两级桶只对 agent 生效、503 映射与 PG 零写入。
 * 校验顺序也是被测对象：`403` / `404` / `400` 不会被 `429` 盖住。
 */
class SendMessageApiTest extends ApiTestSupport {

    @Test
    void 好友私聊成功且代发带的是网关生成的id与凭据里的发送者() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);

        String body = sendDm(me, peer.accountId(), "在吗")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.conversation.type").value("dm"))
                .andExpect(jsonPath("$.conversation.id").value(peer.accountId()))
                .andExpect(jsonPath("$.sent_at").exists())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        long messageId = ((Number) JsonPath.read(body, "$.message_id")).longValue();
        assertThat(messageId).isPositive();
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isEqualTo("/messages");
        Map<String, Object> sent = JsonPath.read(TestStack.TURMS_ADMIN.lastBody(), "$");
        assertThat(((Number) sent.get("id")).longValue()).isEqualTo(messageId);
        assertThat(((Number) sent.get("senderId")).longValue()).isEqualTo(me.accountId());
        assertThat(((Number) sent.get("targetId")).longValue()).isEqualTo(peer.accountId());
        assertThat(sent.get("isGroupMessage")).isEqualTo(false);
        assertThat(sent.get("senderDeviceType")).isEqualTo("DESKTOP");
        assertThat(sent.get("text")).isEqualTo("在吗");
    }

    @Test
    void 对端拉黑我之后私聊回blocked而不是not_friend() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);
        mockMvc.perform(post("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(peer.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(me.accountId())))
                .andExpect(status().isCreated());

        sendDm(me, peer.accountId(), "在吗")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("blocked"));
        // 拉黑判断也在代发之前，没有多出一次 Admin 调用
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isNotEqualTo("/messages");
    }

    @Test
    void 非好友私聊被拒且根本没碰Turms() throws Exception {
        Caller me = newCaller();
        Caller stranger = newCaller();

        sendDm(me, stranger.accountId(), "在吗")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_friend"));
        // 授权拒绝发生在代发之前：最后一次 Admin 调用还是注册时建用户那一次
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isNotEqualTo("/messages");
    }

    @Test
    void 群消息要求有效成员且被移出后立即被拒() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner);

        sendRoom(member, roomId, "我还没进群")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));

        addMember(owner, roomId, member.accountId());
        sendRoom(member, roomId, "进群了")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.conversation.type").value("room"))
                .andExpect(jsonPath("$.conversation.id").value(roomId));
        // 投递句柄是 Turms 的 group id，不是对外的 room_id
        long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        Map<String, Object> roomSent = JsonPath.read(TestStack.TURMS_ADMIN.lastBody(), "$");
        assertThat(((Number) roomSent.get("targetId")).longValue()).isEqualTo(turmsGroupId);
        assertThat(roomSent.get("isGroupMessage")).isEqualTo(true);

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/" + member.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isNoContent());

        // 授权事实现查 PG：移除之后的下一条立刻被拒
        sendRoom(member, roomId, "还能发吗")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));
    }

    @Test
    void 群还没拿到Turms句柄时发送回503且根本不碰Turms() throws Exception {
        Caller owner = newCaller();
        long roomId = createRoom(owner);
        // 投影失败会留在 pending 且 turms_group_id 为空：此时没有可用的投递句柄
        jdbc.update("update room_info set turms_group_id = null, turms_sync_state = 'pending' where id = ?", roomId);

        sendRoom(owner, roomId, "句柄还没回填")
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isNotEqualTo("/messages");
    }

    @Test
    void 会话解析的四条错误各有自己的码() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();

        sendDm(me, 99999999, "在吗")
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
        sendDm(me, me.accountId(), "自言自语")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("id"));
        sendRoom(me, 99999999, "有人在吗")
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
        mockMvc.perform(post("/api/conversations/channel/" + peer.accountId() + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"hello"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("type"));
    }

    @Test
    void 正文空白与超长都是校验失败() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);

        sendDm(me, peer.accountId(), "   ")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("text"));
        sendDm(me, peer.accountId(), "好".repeat(501))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("text"));
    }

    @Test
    void 冻结账号发不出去() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        sendDm(me, peer.accountId(), "在吗")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
    }

    @Test
    void Turms没确认时回503() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);

        TestStack.TURMS_ADMIN.respondWith(500);
        sendDm(me, peer.accountId(), "在吗")
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));
    }

    @Test
    void agent用密钥超会话级桶回429但同账号的归属者不受影响() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        Caller peer = newCaller();
        // 好友关系由 peer 发起、agent 用密钥应答：好友申请才进账号级桶，应答不进，
        // 这样 agent 的账号级桶还是满额 3 次，第三次发言撞的是会话级桶（测试里 2 次/分钟）
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(peer.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(agent.accountId())))
                .andExpect(status().isCreated());
        mockMvc.perform(post("/api/friendships/" + peer.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isOk());

        // 会话级桶在测试里是 2 次/分钟，第三次撞桶
        for (int i = 0; i < 2; i++) {
            sendDm(agent.accountKey(), peer.accountId(), "第 " + i + " 条")
                    .andExpect(status().isCreated());
        }
        sendDm(agent.accountKey(), peer.accountId(), "超了")
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("rate_limited"));

        // 同一个账号由归属者切换进来时来源是 owner，不进任何 agent 桶
        sendDm(switchInto(owner, agent.accountId()), peer.accountId(), "本人来说一句")
                .andExpect(status().isCreated());
    }

    @Test
    void 授权拒绝不消耗配额也不会被429盖住() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        Caller stranger = newCaller();

        // 先撞满会话级桶之外的分支：非好友被拒时不进桶，所以连发三次都不该有 429
        for (int i = 0; i < 5; i++) {
            sendDm(agent.accountKey(), stranger.accountId(), "陌生人 " + i)
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.code").value("not_friend"));
        }
    }

    @Test
    void 设备类型缺省桌面端且可以按头声明() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        befriend(me, peer);

        sendDm(me, peer.accountId(), "默认")
                .andExpect(status().isCreated());
        assertThat(JsonPath.<Object>read(TestStack.TURMS_ADMIN.lastBody(), "$.senderDeviceType"))
                .isEqualTo("DESKTOP");

        mockMvc.perform(post("/api/conversations/dm/" + peer.accountId() + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .header("X-Device-Type", "browser")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"来自网页"}
                                """))
                .andExpect(status().isCreated());
        assertThat(JsonPath.<Object>read(TestStack.TURMS_ADMIN.lastBody(), "$.senderDeviceType"))
                .isEqualTo("BROWSER");

        mockMvc.perform(post("/api/conversations/dm/" + peer.accountId() + "/messages")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .header("X-Device-Type", "toaster")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"text":"来自烤面包机"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("X-Device-Type"));
    }

    @Test
    void 发言不写PG() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner);
        addMember(owner, roomId, member.accountId());
        Map<String, Object> before = roomSnapshot(roomId);

        sendRoom(member, roomId, "一条消息")
                .andExpect(status().isCreated());

        assertThat(roomSnapshot(roomId)).isEqualTo(before);
    }

    private Map<String, Object> roomSnapshot(long roomId) {
        return Map.of(
                "room", jdbc.queryForMap("select name, owner_account_id, turms_group_id, turms_sync_state, "
                        + "updated_at from room_info where id = ?", roomId),
                "members", jdbc.queryForObject("select count(*) from room_member where room_id = ?",
                        Long.class, roomId),
                "mirror", jdbc.queryForObject("select count(*) from account_room where room_id = ?",
                        Long.class, roomId),
                "messages", jdbc.queryForObject("select count(*) from information_schema.tables "
                        + "where table_name ilike '%message%'", Long.class));
    }

    private ResultActions sendDm(Caller me, long peerAccountId, String text) throws Exception {
        return sendDm(me.token(), peerAccountId, text);
    }

    private ResultActions sendDm(String credential, long peerAccountId, String text) throws Exception {
        return mockMvc.perform(post("/api/conversations/dm/" + peerAccountId + "/messages")
                .header(HttpHeaders.AUTHORIZATION, bearer(credential))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"text":"%s"}
                        """.formatted(text)));
    }

    private ResultActions sendRoom(Caller me, long roomId, String text) throws Exception {
        return mockMvc.perform(post("/api/conversations/room/" + roomId + "/messages")
                .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"text":"%s"}
                        """.formatted(text)));
    }

    /** 归属者切进名下 agent 账号，拿到该账号的登录 JWT（#3 的归属者形态）。 */
    private String switchInto(Caller owner, long accountId) throws Exception {
        String body = mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(accountId)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return JsonPath.read(body, "$.login_token");
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
