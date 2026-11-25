package im.mondchat.biz.service.projection;

import im.mondchat.biz.entity.DomainEvent;
import im.mondchat.biz.mapper.projection.DomainEventMapper;
import java.time.OffsetDateTime;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 投影事件的写入端：调用方在自己的 `@Transactional` 里调用这几个方法，
 * 事件与业务变更同一次提交（docs/truth/backend/projection.md）。payload 存「目标状态」，重复投递收敛。
 */
@Component
@RequiredArgsConstructor
public class ProjectionEvents {

    public static final String FRIENDSHIP = "friendship";
    public static final String BLOCKLIST = "blocklist";
    public static final String ROOM_MEMBER = "room_member";
    public static final String ACCOUNT = "account";

    public static final String FRIENDSHIP_CHANGED = "friendship.changed";
    public static final String BLOCKLIST_CHANGED = "blocklist.changed";
    public static final String ROOM_MEMBER_CHANGED = "room_member.changed";
    public static final String ACCOUNT_CREATED = "account.created";

    private final DomainEventMapper events;

    /** 好友成立或不成立；`blocked` 表示 PG 里这一对当前是否仍处于拉黑，决定删行后要不要补回只带 blockDate 的行。 */
    public void friendshipChanged(long one, long another, boolean accepted, boolean blocked) {
        long lower = Math.min(one, another);
        long higher = Math.max(one, another);
        append(FRIENDSHIP, lower + ":" + higher, FRIENDSHIP_CHANGED,
                "{\"a\":" + lower + ",\"b\":" + higher + ",\"accepted\":" + accepted
                        + ",\"blocked\":" + blocked + "}");
    }

    public void blocklistChanged(long ownerId, long blockedId, boolean blockedNow, boolean friends) {
        append(BLOCKLIST, ownerId + ":" + blockedId, BLOCKLIST_CHANGED,
                "{\"owner\":" + ownerId + ",\"blocked\":" + blockedId
                        + ",\"blocked_now\":" + blockedNow + ",\"friends\":" + friends + "}");
    }

    /** `turmsGroupId` 为空时派发器会退避重试，等群投影把句柄回填后再落。 */
    public void roomMemberChanged(long roomId, long accountId, Long turmsGroupId, boolean member) {
        append(ROOM_MEMBER, roomId + ":" + accountId, ROOM_MEMBER_CHANGED,
                "{\"room_id\":" + roomId + ",\"account_id\":" + accountId + ",\"turms_group_id\":"
                        + (turmsGroupId == null ? "null" : turmsGroupId) + ",\"member\":" + member + "}");
    }

    public void accountCreated(long accountId, String displayName) {
        append(ACCOUNT, Long.toString(accountId), ACCOUNT_CREATED,
                "{\"account_id\":" + accountId + ",\"display_name\":\"" + displayName.replace("\"", "'")
                        + "\"}");
    }

    private void append(String aggregateType, String aggregateId, String eventType, String payload) {
        OffsetDateTime now = OffsetDateTime.now();
        events.insertEvent(DomainEvent.builder()
                .aggregateType(aggregateType)
                .aggregateId(aggregateId)
                .eventType(eventType)
                .payload(payload)
                .createdAt(now)
                .attemptCount(0)
                .nextAttemptAt(now)
                .build());
    }
}
