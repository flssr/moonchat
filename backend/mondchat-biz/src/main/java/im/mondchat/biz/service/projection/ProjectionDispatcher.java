package im.mondchat.biz.service.projection;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.config.ProjectionProperties;
import im.mondchat.biz.entity.DomainEvent;
import im.mondchat.biz.mapper.projection.DomainEventMapper;
import java.time.OffsetDateTime;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * 投影派发器：单 worker 按 id 顺序取未处理事件，写进 Turms 的读模型（docs/truth/backend/projection.md）。
 * 失败指数退避，10 次后转日级重试，交对账兜底；**永不反写 PG**。
 * 单 worker 不加 `SKIP LOCKED`：多实例时再加（已知上限）。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ProjectionDispatcher {

    private static final int MAX_ATTEMPTS = 10;
    private static final long EPOCH_ZERO = 0L;

    private static final JsonMapper JSON = JsonMapper.builder().build();

    private final DomainEventMapper events;
    private final TurmsAdminClient admin;
    private final ProjectionProperties properties;

    @Scheduled(fixedDelayString = "${mondchat.projection.dispatch-interval-ms:2000}")
    public void dispatchPending() {
        if (!properties.enabled()) {
            return;
        }
        List<DomainEvent> batch = events.selectList(new LambdaQueryWrapper<DomainEvent>()
                .isNull(DomainEvent::getProcessedAt)
                .le(DomainEvent::getNextAttemptAt, OffsetDateTime.now())
                .orderByAsc(DomainEvent::getId)
                .last("limit " + properties.batchSize()));
        for (DomainEvent event : batch) {
            try {
                apply(event);
                events.update(null, new LambdaUpdateWrapper<DomainEvent>()
                        .eq(DomainEvent::getId, event.getId())
                        .set(DomainEvent::getProcessedAt, OffsetDateTime.now())
                        .set(DomainEvent::getLastError, null));
            } catch (RuntimeException e) {
                reschedule(event, e);
            }
        }
    }

    private void apply(DomainEvent event) {
        JsonNode payload = JSON.readTree(event.getPayload());
        switch (event.getEventType()) {
            case ProjectionEvents.ACCOUNT_CREATED -> applyAccount(payload);
            case ProjectionEvents.FRIENDSHIP_CHANGED -> applyFriendship(event, payload);
            case ProjectionEvents.BLOCKLIST_CHANGED -> applyBlocklist(event, payload);
            case ProjectionEvents.ROOM_MEMBER_CHANGED -> applyRoomMember(payload);
            default -> log.warn("未知的投影事件类型，已丢弃：{}", event.getEventType());
        }
    }

    private void applyAccount(JsonNode payload) {
        long accountId = payload.path("account_id").asLong();
        if (!admin.userExists(accountId)) {
            admin.createUser(accountId, payload.path("display_name").asString());
        }
    }

    private void applyFriendship(DomainEvent event, JsonNode payload) {
        long a = payload.path("a").asLong();
        long b = payload.path("b").asLong();
        boolean accepted = payload.path("accepted").asBoolean();
        boolean blocked = payload.path("blocked").asBoolean();
        long establishment = event.getCreatedAt().toInstant().toEpochMilli();
        if (accepted) {
            upsertFriendship(a, b, establishment);
            upsertFriendship(b, a, establishment);
            return;
        }
        // 删好友必须物理删行：Turms 的好友判定是「行存在且 blockDate 为空」，不看 establishmentDate
        admin.deleteRelationships(List.of(new long[] {a, b}, new long[] {b, a}));
        if (blocked) {
            // 仍在拉黑：补回只带 blockDate 的两行（epoch-0 的 establishmentDate 表示不是好友）
            admin.createRelationship(a, b, establishment, EPOCH_ZERO);
            admin.createRelationship(b, a, establishment, EPOCH_ZERO);
        }
    }

    private void upsertFriendship(long ownerId, long relatedId, long establishment) {
        TurmsAdminClient.Relationship row = admin.queryRelationship(ownerId, relatedId);
        if (row == null) {
            admin.createRelationship(ownerId, relatedId, null, establishment);
        } else {
            // 只写 establishmentDate：blockDate 传 null 是 no-op，不会把既有拉黑弄丢
            admin.updateRelationship(ownerId, relatedId, null, establishment);
        }
    }

    private void applyBlocklist(DomainEvent event, JsonNode payload) {
        long ownerId = payload.path("owner").asLong();
        long blockedId = payload.path("blocked").asLong();
        boolean blockedNow = payload.path("blocked_now").asBoolean();
        boolean friends = payload.path("friends").asBoolean();
        long now = event.getCreatedAt().toInstant().toEpochMilli();
        TurmsAdminClient.Relationship row = admin.queryRelationship(ownerId, blockedId);
        if (blockedNow) {
            if (row == null) {
                // 拉黑陌生人：ed 用 epoch-0，免得 Turms 的默认值把这一行变成「好友」
                admin.createRelationship(ownerId, blockedId, now, EPOCH_ZERO);
            } else {
                admin.updateRelationship(ownerId, blockedId, now, null);
            }
            return;
        }
        if (friends) {
            // 取消拉黑但仍是好友：只有 epoch-0 才会 unset（null 是 no-op）
            admin.updateRelationship(ownerId, blockedId, EPOCH_ZERO, null);
        } else {
            admin.deleteRelationships(List.of(new long[] {ownerId, blockedId}));
        }
    }

    private void applyRoomMember(JsonNode payload) {
        long turmsGroupId = payload.path("turms_group_id").asLong(0);
        if (turmsGroupId <= 0) {
            // 群投影还没回填 group 句柄：抛出去让事件退避重试，别拿 room_id 去撞
            throw new IllegalStateException("群还没有 turms_group_id，等投影回填后再落成员");
        }
        long accountId = payload.path("account_id").asLong();
        if (payload.path("member").asBoolean()) {
            admin.addGroupMember(turmsGroupId, accountId);
        } else {
            admin.removeGroupMember(turmsGroupId, accountId);
        }
    }

    private void reschedule(DomainEvent event, RuntimeException e) {
        int attempt = event.getAttemptCount() == null ? 1 : event.getAttemptCount() + 1;
        long delaySeconds = attempt >= MAX_ATTEMPTS
                ? 86_400L
                : Math.min(1L << Math.min(attempt, 8), 300L);
        events.update(null, new LambdaUpdateWrapper<DomainEvent>()
                .eq(DomainEvent::getId, event.getId())
                .set(DomainEvent::getAttemptCount, attempt)
                .set(DomainEvent::getNextAttemptAt, OffsetDateTime.now().plusSeconds(delaySeconds))
                .set(DomainEvent::getLastError, truncate(e.toString())));
        log.warn("投影事件派发失败，{} 秒后重试：id={} type={} attempt={}",
                delaySeconds, event.getId(), event.getEventType(), attempt, e);
    }

    private static String truncate(String message) {
        return message.length() <= 500 ? message : message.substring(0, 500);
    }
}
