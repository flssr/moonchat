package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import im.moonchat.biz.service.turms.RoomProjectionService;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * 投影失败不回滚业务写，`pending` 被重放收敛（docs/truth/backend/room.md）。
 * 重放器在测试里手动调一次，不靠 30 秒的定时器。
 */
class RoomProjectionReplayTest extends ApiTestSupport {

    @Autowired
    RoomProjectionService projectionService;

    @Test
    void 建群时Turms挂了群仍在PG且重放后收敛() throws Exception {
        Caller owner = newCaller();
        TestStack.TURMS_ADMIN.respondWith(500);

        long roomId = createRoom(owner, "读书会");

        // 201 只表示「PG 里群已成立」：群在、群主是成员、投影还欠着
        assertThat(jdbc.queryForObject("select turms_sync_state from room_info where id = ?", String.class, roomId))
                .isEqualTo("pending");
        assertThat(jdbc.queryForObject("select turms_group_id from room_info where id = ?", Long.class, roomId))
                .isNull();
        assertThat(jdbc.queryForObject(
                "select count(*) from room_member where room_id = ? and deleted_at is null",
                Long.class, roomId)).isEqualTo(1);

        TestStack.TURMS_ADMIN.reset();
        projectionService.replayPending();

        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(turmsGroupId).isNotNull();
        assertThat(jdbc.queryForObject("select turms_sync_state from room_info where id = ?", String.class, roomId))
                .isEqualTo("synced");
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).containsExactly(owner.accountId());
    }

    @Test
    void 拉人时Turms挂了成员仍在群里且重放后Turms集合一致() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner, "读书会");
        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);

        TestStack.TURMS_ADMIN.respondWith(500);
        addMember(owner, roomId, member.accountId());

        assertThat(jdbc.queryForObject("select turms_sync_state from room_info where id = ?", String.class, roomId))
                .isEqualTo("pending");
        assertThat(jdbc.queryForObject(
                "select count(*) from room_member where room_id = ? and deleted_at is null",
                Long.class, roomId)).isEqualTo(2);
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).containsExactly(owner.accountId());

        TestStack.TURMS_ADMIN.reset();
        projectionService.replayPending();

        assertThat(jdbc.queryForObject("select turms_sync_state from room_info where id = ?", String.class, roomId))
                .isEqualTo("synced");
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId))
                .containsExactlyInAnyOrder(owner.accountId(), member.accountId());
    }

    @Test
    void 群在Turms侧被丢掉后重放按PG重建并回填新的群id() throws Exception {
        Caller owner = newCaller();
        Caller member = newCaller();
        long roomId = createRoom(owner, "读书会");
        addMember(owner, roomId, member.accountId());
        Long lostGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);

        TestStack.TURMS_ADMIN.forgetGroup(lostGroupId);
        projectionService.replayPending();
        // 群不在 Turms 时，重放不会自己跑：得靠一次成员变化把它标回 pending
        assertThat(jdbc.queryForObject("select turms_group_id from room_info where id = ?", Long.class, roomId))
                .isEqualTo(lostGroupId);

        jdbc.update("update room_info set turms_sync_state = 'pending' where id = ?", roomId);
        projectionService.replayPending();

        Long rebuiltGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(rebuiltGroupId).isNotEqualTo(lostGroupId);
        assertThat(TestStack.TURMS_ADMIN.membersOf(rebuiltGroupId))
                .containsExactlyInAnyOrder(owner.accountId(), member.accountId());
        assertThat(jdbc.queryForObject("select turms_sync_state from room_info where id = ?", String.class, roomId))
                .isEqualTo("synced");
    }

    private long createRoom(Caller owner, String name) throws Exception {
        String body = mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s"}
                                """.formatted(name)))
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
