package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * #12–#18 群七条：建群回填 `turms_group_id`、三张表同事务、成员集合与 Turms 投影逐条一致，
 * 以及「成员操作只有真人能做」与群主不能退群。
 */
class RoomApiTest extends ApiTestSupport {

    @Test
    void 建群后回填turms群id且群主是成员() throws Exception {
        Caller owner = newCaller();

        long roomId = createRoom(owner, "读书会");

        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(turmsGroupId).isNotNull();
        assertThat(jdbc.queryForObject("select turms_sync_state from room_info where id = ?", String.class, roomId))
                .isEqualTo("synced");
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).containsExactly(owner.accountId());
        // 「群主一定是成员」是事务产物：两张成员表都有他，且时间一致
        assertThat(jdbc.queryForObject("""
                select count(*) from room_member m join account_room a
                    on a.account_id = m.account_id and a.room_id = m.room_id
                where m.room_id = ? and m.account_id = ? and m.deleted_at is null
                    and a.joined_at = m.joined_at and a.deleted_at is null
                """, Long.class, roomId, owner.accountId())).isEqualTo(1);

        // 对外的群标识只有 room_id：详情里不出现 turms_group_id / turms_sync_state
        // （列表 #13 例外，它要给出投递句柄，见下一条用例）
        mockMvc.perform(get("/api/rooms/" + roomId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.room_id").value(roomId))
                .andExpect(jsonPath("$.name").value("读书会"))
                .andExpect(jsonPath("$.owner_account_id").value(owner.accountId()))
                .andExpect(jsonPath("$.member_count").value(1))
                .andExpect(jsonPath("$.turms_group_id").doesNotExist())
                .andExpect(jsonPath("$.turms_sync_state").doesNotExist());
    }

    @Test
    void 我的群只看account_room且成员之外看不到群信息() throws Exception {
        Caller owner = newCaller();
        Caller outsider = newCaller();
        long roomId = createRoom(owner, "读书会");
        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(turmsGroupId).isNotNull();

        mockMvc.perform(get("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].room_id").value(roomId))
                .andExpect(jsonPath("$.items[0].joined_at").exists())
                // 群历史/推送归并要的 Turms 句柄：字符串，避免前端 JS 丢精度
                .andExpect(jsonPath("$.items[0].turms_group_id").value(turmsGroupId.toString()));

        mockMvc.perform(get("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(outsider.token())))
                .andExpect(jsonPath("$.items.length()").value(0));

        mockMvc.perform(get("/api/rooms/" + roomId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(outsider.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));
        mockMvc.perform(get("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(outsider.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));
        mockMvc.perform(get("/api/rooms/99999999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
    }

    @Test
    void 拉人后Turms成员集合与有效成员行逐条一致() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner, "读书会");

        addMember(owner, roomId, member.accountId());

        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId))
                .containsExactlyInAnyOrder(owner.accountId(), member.accountId());
        assertThat(jdbc.queryForObject("""
                select count(*) from room_member m join account_room a
                    on a.account_id = m.account_id and a.room_id = m.room_id
                where m.room_id = ? and m.deleted_at is null and a.deleted_at is null
                """, Long.class, roomId)).isEqualTo(2);

        mockMvc.perform(get("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(2))
                .andExpect(jsonPath("$.page").value(1))
                .andExpect(jsonPath("$.size").value(50))
                .andExpect(jsonPath("$.items.length()").value(2));
    }

    @Test
    void 已在群里是冲突不存在的账号是未找到非成员拉人是禁止() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        Caller outsider = newCaller();
        long roomId = createRoom(owner, "读书会");
        addMember(owner, roomId, member.accountId());

        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(member.accountId())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("conflict"));

        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":99999999}
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));

        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(outsider.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(outsider.accountId())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
    }

    @Test
    void 退群后Turms成员同步减少且再查是not_room_member() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner, "读书会");
        addMember(owner, roomId, member.accountId());

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isNoContent());

        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).containsExactly(owner.accountId());
        assertThat(jdbc.queryForObject("select deleted_at from room_member where room_id = ? and account_id = ?",
                Timestamp.class, roomId, member.accountId())).isNotNull();
        assertThat(jdbc.queryForObject("select deleted_at from account_room where room_id = ? and account_id = ?",
                Timestamp.class, roomId, member.accountId())).isNotNull();

        mockMvc.perform(get("/api/rooms/" + roomId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));
        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("not_room_member"));
    }

    @Test
    void 群主退群与移除自己都是owner_cannot_leave() throws Exception {
        Caller owner = newCaller();
        long roomId = createRoom(owner, "读书会");

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("owner_cannot_leave"));

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/" + owner.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("owner_cannot_leave"));
    }

    @Test
    void 移除成员只有群主能做且移完是未找到() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        Caller other = newCaller();
        long roomId = createRoom(owner, "读书会");
        addMember(owner, roomId, member.accountId());
        addMember(owner, roomId, other.accountId());

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/" + other.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/" + other.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/" + other.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));

        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId))
                .containsExactlyInAnyOrder(owner.accountId(), member.accountId());
    }

    @Test
    void 重进群复用原行并刷新加入时间() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner, "读书会");
        addMember(owner, roomId, member.accountId());
        Timestamp firstJoin = jdbc.queryForObject(
                "select joined_at from room_member where room_id = ? and account_id = ?",
                Timestamp.class, roomId, member.accountId());

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(member.token())))
                .andExpect(status().isNoContent());
        addMember(owner, roomId, member.accountId());

        Map<String, Object> reused = jdbc.queryForMap("""
                select count(*) over () as rows, joined_at, deleted_at
                from room_member where room_id = ? and account_id = ?
                """, roomId, member.accountId());
        assertThat(((Number) reused.get("rows")).intValue()).isEqualTo(1);
        assertThat(reused.get("deleted_at")).isNull();
        assertThat((Timestamp) reused.get("joined_at")).isAfter(firstJoin);
    }

    @Test
    void agent来源在四条写接口上都是禁止() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        long roomId = createRoom(owner, "读书会");

        mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"agent 的群"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));

        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(agent.accountId())))
                .andExpect(status().isForbidden());

        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/" + agent.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isForbidden());
        mockMvc.perform(delete("/api/rooms/" + roomId + "/members/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isForbidden());
    }

    @Test
    void 成员列表带isfriend且分页取1到100() throws Exception {
        Caller owner = newCaller();
        Caller friend = newCaller();
        Caller stranger = newCaller();
        long roomId = createRoom(owner, "读书会");
        requestFriend(owner, friend.accountId());
        acceptFriend(friend, owner.accountId());
        addMember(owner, roomId, friend.accountId());
        addMember(owner, roomId, stranger.accountId());

        mockMvc.perform(get("/api/rooms/" + roomId + "/members?page=1&size=10")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(3))
                .andExpect(jsonPath("$.items[?(@.account_id == %d)].is_friend".formatted(friend.accountId()))
                        .value(true))
                .andExpect(jsonPath("$.items[?(@.account_id == %d)].is_friend".formatted(stranger.accountId()))
                        .value(false));

        mockMvc.perform(get("/api/rooms/" + roomId + "/members?page=2&size=2")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(3))
                .andExpect(jsonPath("$.items.length()").value(1));

        mockMvc.perform(get("/api/rooms/" + roomId + "/members?page=0")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("page"));
        mockMvc.perform(get("/api/rooms/" + roomId + "/members?size=101")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("size"));
    }

    @Test
    void 群名空白或超长是校验失败() throws Exception {
        Caller owner = newCaller();

        mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"   "}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("name"));

        mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s"}
                                """.formatted("群".repeat(21))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("name"));
    }

    @Test
    void 冻结的账号建不了群也拉不了人() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner, "读书会");

        jdbc.update("update account_info set status = 'frozen' where account_id = ?", owner.accountId());
        mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"冻结的群"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(member.accountId())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
    }

    private long createRoom(Caller owner, String name) throws Exception {
        String body = mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s"}
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.owner_account_id").value(owner.accountId()))
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
