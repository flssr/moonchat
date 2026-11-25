package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import im.mondchat.biz.service.projection.ProjectionDispatcher;
import im.mondchat.biz.service.projection.ProjectionEvents;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.web.servlet.ResultActions;

/** #81 注销后端：硬删、级联 agent、关系清理、旧凭据失效与 Turms outbox。 */
class AccountDeletionApiTest extends ApiTestSupport {

    @Autowired
    ProjectionDispatcher dispatcher;

    @Autowired
    ProjectionEvents projectionEvents;

    @Autowired
    StringRedisTemplate redis;

    @Test
    void 硬删真人与名下agent并释放邮箱() throws Exception {
        String email = uniqueEmail();
        Caller me = callerWithEmail(email);
        Caller other = newCaller();
        Agent agent = newAgent(me, "小助手");
        long nestedAgentId = insertAgent(agent.accountId(), "嵌套 agent", Instant.now());

        deleteAccount(me.token(), "secret123").andExpect(status().isNoContent());

        assertAccountRowsAbsent(me.accountId());
        assertAccountRowsAbsent(agent.accountId());
        assertAccountRowsAbsent(nestedAgentId);
        assertThat(jdbc.queryForObject("""
                select count(*) from domain_event
                where event_type = 'account.created' and aggregate_id in (?, ?, ?)
                """, Long.class, Long.toString(me.accountId()), Long.toString(agent.accountId()),
                Long.toString(nestedAgentId))).isZero();
        projectionEvents.accountCreated(me.accountId(), "late event must not revive");
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"secret123"}
                                """.formatted(email)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
        register(email, "secret123", "重新注册");

        mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/accounts/" + other.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"孤儿 agent"}
                                """))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isUnauthorized());
        deleteAccount(me.token(), "secret123").andExpect(status().isUnauthorized());

        dispatchUntilAccountDeleted(me.accountId());
        dispatchUntilAccountDeleted(agent.accountId());
        dispatchUntilAccountDeleted(nestedAgentId);
        assertThat(TestStack.TURMS_ADMIN.lastDeleteUserQuery()).contains("deleteLogically=false");
        assertThat(TestStack.TURMS_ADMIN.hasUser(me.accountId())).isFalse();
        assertThat(TestStack.TURMS_ADMIN.hasUser(agent.accountId())).isFalse();
        assertThat(TestStack.TURMS_ADMIN.hasUser(nestedAgentId)).isFalse();
    }

    @Test
    void 清理好友申请黑名单群成员和账号群镜像() throws Exception {
        Caller me = newCaller();
        Caller other = newCaller();
        Agent agent = newAgent(me, "小助手");
        long roomId = createRoom(other);
        addMember(other, roomId, me.accountId());
        addMember(other, roomId, agent.accountId());
        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        assertThat(turmsGroupId).isNotNull();

        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(other.accountId())))
                .andExpect(status().isCreated());
        mockMvc.perform(post("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(other.accountId())))
                .andExpect(status().isCreated());
        mockMvc.perform(post("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(other.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(me.accountId())))
                .andExpect(status().isCreated());

        deleteAccount(me.token(), "secret123").andExpect(status().isNoContent());

        assertThat(jdbc.queryForObject("""
                select count(*) from friendship
                where account_id in (?, ?) or peer_account_id in (?, ?)
                """, Long.class, me.accountId(), agent.accountId(), me.accountId(), agent.accountId()))
                .isZero();
        assertThat(jdbc.queryForObject("""
                select count(*) from friendship_reverse
                where account_id in (?, ?) or peer_account_id in (?, ?)
                """, Long.class, me.accountId(), agent.accountId(), me.accountId(), agent.accountId()))
                .isZero();
        assertThat(jdbc.queryForObject("""
                select count(*) from blocklist
                where owner_account_id in (?, ?) or blocked_account_id in (?, ?)
                """, Long.class, me.accountId(), agent.accountId(), me.accountId(), agent.accountId()))
                .isZero();
        assertThat(jdbc.queryForObject("select count(*) from room_member where account_id in (?, ?)",
                Long.class, me.accountId(), agent.accountId())).isZero();
        assertThat(jdbc.queryForObject("select count(*) from account_room where account_id in (?, ?)",
                Long.class, me.accountId(), agent.accountId())).isZero();
        assertThat(jdbc.queryForObject("select owner_account_id from room_info where id = ?",
                Long.class, roomId)).isEqualTo(other.accountId());

        dispatchUntilAccountDeleted(me.accountId());
        dispatchUntilAccountDeleted(agent.accountId());
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).containsExactly(other.accountId());
        assertThat(TestStack.TURMS_ADMIN.hasUser(me.accountId())).isFalse();
        assertThat(TestStack.TURMS_ADMIN.hasUser(agent.accountId())).isFalse();
    }

    @Test
    void 群主注销返回409且不删数据() throws Exception {
        Caller owner = newCaller();
        createRoom(owner);

        deleteAccount(owner.token(), "secret123")
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("owner_cannot_delete_account"));

        assertThat(jdbc.queryForObject("select count(*) from account where id = ?", Long.class, owner.accountId()))
                .isEqualTo(1);
    }

    @Test
    void 注销会等待子树账号行锁释放() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try (Connection lock = jdbc.getDataSource().getConnection()) {
            lock.setAutoCommit(false);
            try (PreparedStatement statement = lock.prepareStatement("select id from account where id = ? for update")) {
                statement.setLong(1, agent.accountId());
                statement.executeQuery().close();
            }
            Future<Integer> deleted = pool.submit(() -> deleteAccount(owner.token(), "secret123")
                    .andReturn().getResponse().getStatus());

            assertThatThrownBy(() -> deleted.get(300, TimeUnit.MILLISECONDS))
                    .isInstanceOf(TimeoutException.class);
            lock.commit();
            assertThat(deleted.get(5, TimeUnit.SECONDS)).isEqualTo(204);
            assertAccountRowsAbsent(owner.accountId());
            assertAccountRowsAbsent(agent.accountId());
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void 存量agent拥有的群也会阻止整棵账号树注销() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        Long roomId = jdbc.queryForObject("""
                insert into room_info (name, owner_account_id) values ('agent 遗留群', ?) returning id
                """, Long.class, agent.accountId());
        jdbc.update("insert into room_member (room_id, account_id) values (?, ?)", roomId, agent.accountId());
        jdbc.update("insert into account_room (account_id, room_id) values (?, ?)", agent.accountId(), roomId);

        deleteAccount(owner.token(), "secret123")
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("owner_cannot_delete_account"));

        assertThat(jdbc.queryForObject("select count(*) from account where id in (?, ?)",
                Long.class, owner.accountId(), agent.accountId())).isEqualTo(2);
    }

    @Test
    void agent密钥与切进agent的登录JWT都不能注销() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        String session = mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(agent.accountId())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        String agentLoginToken = JsonPath.read(session, "$.login_token");

        deleteAccount(agent.accountKey(), "secret123")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
        deleteAccount(agentLoginToken, "secret123")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
        mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agentLoginToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"嵌套 agent"}
                                """))
                .andExpect(status().isForbidden());
        mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agentLoginToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"agent 群"}
                                """))
                .andExpect(status().isForbidden());
        mockMvc.perform(post("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agentLoginToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(owner.accountId())))
                .andExpect(status().isForbidden());
        assertThat(jdbc.queryForObject("select count(*) from account where id = ?", Long.class, agent.accountId()))
                .isEqualTo(1);
    }

    @Test
    void 密码错误用独立错误码且不清会话() throws Exception {
        Caller me = newCaller();

        deleteAccount(me.token(), "wrong-password")
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("invalid_password"));
        mockMvc.perform(get("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk());
    }

    @Test
    void 注销确认按账号限频且失败也计数() throws Exception {
        Caller me = newCaller();

        deleteAccount(me.token(), "wrong-password").andExpect(status().isUnauthorized());
        assertThat(redis.getExpire("mondchat:ratelimit:account-deletion:" + me.accountId())).isPositive();
        deleteAccount(me.token(), "wrong-password").andExpect(status().isUnauthorized());
        deleteAccount(me.token(), "wrong-password")
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("rate_limited"));
        assertThat(jdbc.queryForObject("select count(*) from account where id = ?", Long.class, me.accountId()))
                .isEqualTo(1);
    }

    @Test
    void 冻结账号仍可注销() throws Exception {
        Caller me = newCaller();
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        deleteAccount(me.token(), "secret123").andExpect(status().isNoContent());

        assertAccountRowsAbsent(me.accountId());
    }

    @Test
    void 退群事件先失败而用户删除成功后可重试清理() throws Exception {
        Caller me = newCaller();
        Caller owner = newCaller();
        long roomId = createRoom(owner);
        addMember(owner, roomId, me.accountId());
        Long turmsGroupId = jdbc.queryForObject("select turms_group_id from room_info where id = ?",
                Long.class, roomId);
        TestStack.TURMS_ADMIN.failNext("DELETE", "/groups/members", 500);

        deleteAccount(me.token(), "secret123").andExpect(status().isNoContent());
        dispatcher.dispatchPending();

        assertThat(TestStack.TURMS_ADMIN.hasUser(me.accountId())).isFalse();
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).contains(me.accountId());
        Map<String, Object> event = jdbc.queryForMap("""
                select id, attempt_count, processed_at from domain_event
                where aggregate_type = 'room_member' and aggregate_id = ?
                order by id desc limit 1
                """, roomId + ":" + me.accountId());
        assertThat(event.get("processed_at")).isNull();
        assertThat(((Number) event.get("attempt_count")).intValue()).isEqualTo(1);

        jdbc.update("update domain_event set next_attempt_at = now() where id = ?", event.get("id"));
        for (int i = 0; i < 30; i++) {
            dispatcher.dispatchPending();
            Map<String, Object> current = jdbc.queryForMap("""
                    select attempt_count, processed_at from domain_event where id = ?
                    """, event.get("id"));
            if (current.get("processed_at") != null) {
                break;
            }
        }
        assertThat(TestStack.TURMS_ADMIN.membersOf(turmsGroupId)).doesNotContain(me.accountId());
    }

    @Test
    void Turms删除失败由outbox重试且旧事件不会复活账号() throws Exception {
        Caller me = newCaller();
        TestStack.TURMS_ADMIN.respondWith(500);

        deleteAccount(me.token(), "secret123").andExpect(status().isNoContent());
        Map<String, Object> failed = dispatchUntilAccountDeleted(me.accountId());
        assertThat(failed.get("processed_at")).isNull();
        assertThat(((Number) failed.get("attempt_count")).intValue()).isEqualTo(1);
        assertThat(TestStack.TURMS_ADMIN.hasUser(me.accountId())).isTrue();

        TestStack.TURMS_ADMIN.reset();
        jdbc.update("update domain_event set next_attempt_at = now() where id = ?", failed.get("id"));
        Map<String, Object> recovered = null;
        for (int i = 0; i < 30; i++) {
            dispatcher.dispatchPending();
            recovered = jdbc.queryForMap("""
                    select id, event_type, attempt_count, processed_at
                    from domain_event
                    where aggregate_type = 'account' and aggregate_id = ?
                    order by id desc limit 1
                    """, Long.toString(me.accountId()));
            if (recovered.get("processed_at") != null) {
                break;
            }
        }
        assertThat(recovered.get("processed_at")).isNotNull();
        assertThat(TestStack.TURMS_ADMIN.hasUser(me.accountId())).isFalse();
    }

    private Caller callerWithEmail(String email) throws Exception {
        String body = register(email, "secret123", "注销测试");
        long accountId = ((Number) JsonPath.read(body, "$.account_id")).longValue();
        return new Caller(accountId, login(email, "secret123"));
    }

    private ResultActions deleteAccount(String credential, String password) throws Exception {
        return mockMvc.perform(delete("/api/accounts/me")
                .header(HttpHeaders.AUTHORIZATION, bearer(credential))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"password":"%s"}
                        """.formatted(password)));
    }

    private long createRoom(Caller owner) throws Exception {
        String body = mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"注销测试群"}
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return ((Number) JsonPath.read(body, "$.room_id")).longValue();
    }

    private void addMember(Caller operator, long roomId, long accountId) throws Exception {
        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(operator.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(accountId)))
                .andExpect(status().isCreated());
    }

    private void assertAccountRowsAbsent(long accountId) {
        assertThat(jdbc.queryForObject("select count(*) from account where id = ?", Long.class, accountId))
                .isZero();
        assertThat(jdbc.queryForObject("select count(*) from account_info where account_id = ?",
                Long.class, accountId)).isZero();
    }

    private Map<String, Object> dispatchUntilAccountDeleted(long accountId) {
        Map<String, Object> event = null;
        for (int i = 0; i < 30; i++) {
            dispatcher.dispatchPending();
            event = jdbc.queryForMap("""
                    select id, event_type, attempt_count, processed_at
                    from domain_event
                    where aggregate_type = 'account' and aggregate_id = ?
                      and event_type = 'account.deleted'
                    order by id desc limit 1
                    """, Long.toString(accountId));
            boolean settled = "account.deleted".equals(event.get("event_type"))
                    && (event.get("processed_at") != null
                    || ((Number) event.get("attempt_count")).intValue() > 0);
            if (settled) {
                return event;
            }
        }
        return event;
    }
}
