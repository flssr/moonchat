package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import im.mondchat.biz.service.projection.ProjectionDispatcher;
import im.mondchat.biz.service.projection.ProjectionReconciliation;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * 投影地基（docs/truth/backend/projection.md）：业务变更与事件同事务、派发器按目标状态写 Turms、
 * 清拉黑只能用 epoch-0、失败退避。派发器在测试里手动调，定时器被 TestStack 拉长到一小时。
 *
 * <p>派发器一次只取 100 条按 id 升序的事件，而整套测试共用一个库、前面压着别的测试的事件，
 * 所以这里不看「派发一次之后怎样」，而是派发到**这一条**事件有结论为止。
 */
class ProjectionApiTest extends ApiTestSupport {

    private static final String EPOCH_ZERO = "1970-01-01T00:00:00Z";

    @Autowired
    ProjectionDispatcher dispatcher;

    @Autowired
    ProjectionReconciliation reconciliation;

    @Test
    void 接受好友后派发成Turms的两个方向行() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        befriend(one, another);

        Map<String, Object> event = dispatchUntilSettled("friendship", lower(one, another));

        assertThat(event.get("processed_at")).isNotNull();
        Map<String, String> forward = TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId());
        Map<String, String> reverse = TestStack.TURMS_ADMIN.relationship(another.accountId(), one.accountId());
        assertThat(forward).isNotNull();
        assertThat(forward.get("establishmentDate")).isNotBlank();
        assertThat(forward.get("blockDate")).isNull();
        // 发送判定查的是收件人方向那条，所以两个方向都必须在
        assertThat(reverse).isNotNull();
        assertThat(reverse.get("establishmentDate")).isNotBlank();
    }

    @Test
    void 拉黑陌生人只写拉黑不写好友() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        block(one, another);

        assertThat(dispatchUntilSettled("blocklist", one.accountId() + ":" + another.accountId()).get("processed_at"))
                .isNotNull();

        Map<String, String> row = TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId());
        assertThat(row).isNotNull();
        assertThat(row.get("blockDate")).isNotBlank();
        // Turms 建行时 establishmentDate 缺省会填当前时间：必须显式 epoch-0 才不会被当成好友
        assertThat(row.get("establishmentDate")).isEqualTo(EPOCH_ZERO);
    }

    @Test
    void 取消拉黑且不是好友时删掉整行() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        String pair = one.accountId() + ":" + another.accountId();
        block(one, another);
        dispatchUntilSettled("blocklist", pair);

        unblock(one, another);
        // 同一聚合会有两条事件：等到最新那条处理完
        dispatchUntilSettled("blocklist", pair);

        assertThat(TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId())).isNull();
    }

    @Test
    void 取消拉黑但仍是好友时只清拉黑保留好友时间() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        String pair = one.accountId() + ":" + another.accountId();
        befriend(one, another);
        dispatchUntilSettled("friendship", lower(one, another));
        block(one, another);
        dispatchUntilSettled("blocklist", pair);
        assertThat(TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId()).get("blockDate"))
                .isNotBlank();

        unblock(one, another);
        dispatchUntilSettled("blocklist", pair);

        Map<String, String> row = TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId());
        assertThat(row).isNotNull();
        assertThat(row.get("blockDate")).isNull();
        assertThat(row.get("establishmentDate")).isNotBlank();
    }

    @Test
    void 删好友后两个方向都物理删行() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        befriend(one, another);
        dispatchUntilSettled("friendship", lower(one, another));

        mockMvc.perform(delete("/api/friendships/" + another.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(one.token())))
                .andExpect(status().isNoContent());
        dispatchUntilSettled("friendship", lower(one, another));

        assertThat(TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId())).isNull();
        assertThat(TestStack.TURMS_ADMIN.relationship(another.accountId(), one.accountId())).isNull();
    }

    @Test
    void 派发失败时按次数退避而不是丢掉() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        befriend(one, another);
        TestStack.TURMS_ADMIN.respondWith(500);

        Map<String, Object> event = dispatchUntilSettled("friendship", lower(one, another));

        assertThat(((Number) event.get("attempt_count")).intValue()).isEqualTo(1);
        assertThat(event.get("processed_at")).isNull();
        assertThat(event.get("next_attempt_at")).isNotNull();
    }

    @Test
    void 群还没有Turms群id时群成员事件等待重试() throws Exception {
        Caller owner = newCaller();
        // 建群会写一条带 null turms_group_id 的成员事件：不能拿 room_id 去撞
        long roomId = createRoom(owner);

        Map<String, Object> event = dispatchUntilSettled("room_member", roomId + ":" + owner.accountId());

        assertThat(((Number) event.get("attempt_count")).intValue()).isEqualTo(1);
        assertThat(event.get("processed_at")).isNull();
    }

    @Test
    void 账号事件对已存在的Turms用户是幂等的() throws Exception {
        Caller me = newCaller();

        Map<String, Object> event = dispatchUntilSettled("account", Long.toString(me.accountId()));

        assertThat(event.get("processed_at")).isNotNull();
        assertThat(TestStack.TURMS_ADMIN.hasUser(me.accountId())).isTrue();
    }

    @Test
    void 对账发现Turms少行时补一条事件而不是直接写() throws Exception {
        Caller one = newCaller();
        Caller another = newCaller();
        befriend(one, another);
        dispatchUntilSettled("friendship", lower(one, another));
        // 模拟 Turms 读模型丢失：对账只补事件，让派发器按正常路径重建
        TestStack.TURMS_ADMIN.clearRelationships();

        reconciliation.reconcile();

        long pending = jdbc.queryForObject("select count(*) from domain_event where aggregate_type = 'friendship' "
                + "and aggregate_id = ? and processed_at is null", Long.class, lower(one, another));
        assertThat(pending).isPositive();
        assertThat(TestStack.TURMS_ADMIN.relationship(one.accountId(), another.accountId())).isNull();
    }

    /**
     * 派发到这一条事件有结论（处理完或至少重试一次）为止。批量有上限，前面的行要先让开。
     */
    private Map<String, Object> dispatchUntilSettled(String aggregateType, String aggregateId) {
        Map<String, Object> event = null;
        for (int i = 0; i < 30; i++) {
            dispatcher.dispatchPending();
            event = jdbc.queryForMap("select attempt_count, processed_at, next_attempt_at from domain_event "
                    + "where aggregate_type = ? and aggregate_id = ? order by id desc limit 1",
                    aggregateType, aggregateId);
            boolean settled = event.get("processed_at") != null
                    || ((Number) event.get("attempt_count")).intValue() > 0;
            if (settled) {
                return event;
            }
        }
        return event;
    }

    private static String lower(Caller one, Caller another) {
        return Math.min(one.accountId(), another.accountId()) + ":"
                + Math.max(one.accountId(), another.accountId());
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

    private void block(Caller me, Caller target) throws Exception {
        mockMvc.perform(post("/api/blocklist")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(target.accountId())))
                .andExpect(status().isCreated());
    }

    private void unblock(Caller me, Caller target) throws Exception {
        mockMvc.perform(delete("/api/blocklist/" + target.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isNoContent());
    }

    private long createRoom(Caller owner) throws Exception {
        String body = mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"投影群"}
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return ((Number) JsonPath.read(body, "$.room_id")).longValue();
    }
}
