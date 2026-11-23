package im.mondchat.biz.service.projection;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.config.ProjectionProperties;
import im.mondchat.biz.entity.Blocklist;
import im.mondchat.biz.entity.Friendship;
import im.mondchat.biz.entity.RoomInfo;
import im.mondchat.biz.entity.RoomMember;
import im.mondchat.biz.mapper.blocklist.BlocklistMapper;
import im.mondchat.biz.mapper.friendship.FriendshipMapper;
import im.mondchat.biz.mapper.room.RoomInfoMapper;
import im.mondchat.biz.mapper.room.RoomMemberMapper;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 对账：PG 是真相，Turms 是可重建读模型，所以**只修 Turms、永不反写 PG**
 * （docs/truth/backend/projection.md）。少的补一条事件走正常派发，多的直接删。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ProjectionReconciliation {

    private final ProjectionProperties properties;
    private final FriendshipMapper friendshipMapper;
    private final BlocklistMapper blocklistMapper;
    private final RoomInfoMapper roomInfoMapper;
    private final RoomMemberMapper roomMemberMapper;
    private final ProjectionEvents events;
    private final TurmsAdminClient admin;

    @Scheduled(cron = "${mondchat.projection.reconcile-cron:0 0 3 * * *}")
    public void reconcile() {
        if (!properties.enabled()) {
            return;
        }
        int friendships = reconcileFriendships();
        int blocklist = reconcileBlocklist();
        int members = reconcileRoomMembers();
        if (friendships + blocklist + members > 0) {
            log.warn("投影对账补发事件：好友 {}/对 黑名单 {} 条 群成员 {} 条",
                    friendships, blocklist, members);
        }
    }

    /** 每对好友在 Turms 必须有**两个方向**的行：发送判定只看收件人方向那条。 */
    private int reconcileFriendships() {
        List<Friendship> rows = friendshipMapper.selectList(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getStatus, "accepted")
                .isNull(Friendship::getDeletedAt));
        int missing = 0;
        for (Friendship row : rows) {
            long a = row.getAccountId();
            long b = row.getPeerAccountId();
            if (admin.queryRelationship(a, b) == null) {
                events.friendshipChanged(a, b, true, false);
                missing++;
            }
            if (admin.queryRelationship(b, a) == null) {
                events.friendshipChanged(a, b, true, false);
                missing++;
            }
        }
        return missing;
    }

    /** 每条拉黑在 Turms 必须有对应方向且 `blockDate` 非空的行。 */
    private int reconcileBlocklist() {
        List<Blocklist> rows = blocklistMapper.selectList(new LambdaQueryWrapper<>());
        int missing = 0;
        for (Blocklist row : rows) {
            TurmsAdminClient.Relationship relationship =
                    admin.queryRelationship(row.getOwnerAccountId(), row.getBlockedAccountId());
            if (relationship == null || relationship.blockDate() == null) {
                events.blocklistChanged(row.getOwnerAccountId(), row.getBlockedAccountId(), true,
                        isFriend(row.getOwnerAccountId(), row.getBlockedAccountId()));
                missing++;
            }
        }
        return missing;
    }

    /** 群成员按 Turms 句柄比：少的补事件，多的直接删（Turms 侧多出来的行没有业务意义）。 */
    private int reconcileRoomMembers() {
        List<RoomInfo> rooms = roomInfoMapper.selectList(new LambdaQueryWrapper<RoomInfo>()
                .isNotNull(RoomInfo::getTurmsGroupId));
        int changed = 0;
        for (RoomInfo room : rooms) {
            long turmsGroupId = room.getTurmsGroupId();
            Set<Long> actual = admin.groupMemberIds(turmsGroupId);
            Set<Long> expected = new HashSet<>(roomMemberMapper.selectList(
                            new LambdaQueryWrapper<RoomMember>()
                                    .eq(RoomMember::getRoomId, room.getId())
                                    .isNull(RoomMember::getDeletedAt))
                    .stream()
                    .map(RoomMember::getAccountId)
                    .toList());
            for (long accountId : expected) {
                if (!actual.contains(accountId)) {
                    events.roomMemberChanged(room.getId(), accountId, turmsGroupId, true);
                    changed++;
                }
            }
            for (long accountId : actual) {
                if (!expected.contains(accountId)) {
                    admin.removeGroupMember(turmsGroupId, accountId);
                    changed++;
                }
            }
        }
        return changed;
    }

    private boolean isFriend(long one, long another) {
        long lower = Math.min(one, another);
        long higher = Math.max(one, another);
        return friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getAccountId, lower)
                .eq(Friendship::getPeerAccountId, higher)
                .eq(Friendship::getStatus, "accepted")
                .isNull(Friendship::getDeletedAt)) > 0;
    }
}
