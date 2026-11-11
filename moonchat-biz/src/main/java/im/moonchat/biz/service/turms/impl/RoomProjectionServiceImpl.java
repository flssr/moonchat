package im.moonchat.biz.service.turms.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import im.moonchat.biz.client.turms.TurmsAdminClient;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.entity.RoomInfo;
import im.moonchat.biz.entity.RoomMember;
import im.moonchat.biz.entity.TurmsSyncState;
import im.moonchat.biz.mapper.room.RoomInfoMapper;
import im.moonchat.biz.mapper.room.RoomMemberMapper;
import im.moonchat.biz.service.turms.RoomProjectionService;
import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 投影按 PG 重算：`room_member` 的有效行是唯一真相，Turms 的成员集合只是副本。
 * 一次 reconcile 只做三件事——群不在就建、缺的人加进去、多的人移出来。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RoomProjectionServiceImpl implements RoomProjectionService {

    private final RoomInfoMapper roomInfoMapper;
    private final RoomMemberMapper roomMemberMapper;
    private final TurmsAdminClient turmsAdmin;

    @Override
    public void reconcile(long roomId) {
        RoomInfo room = roomInfoMapper.selectById(roomId);
        if (room == null) {
            return;
        }
        try {
            long turmsGroupId = room.getTurmsGroupId() == null || !turmsAdmin.groupExists(room.getTurmsGroupId())
                    ? createGroup(room)
                    : room.getTurmsGroupId();

            Set<Long> wanted = validMemberIds(roomId);
            Set<Long> projected = turmsAdmin.groupMemberIds(turmsGroupId);
            wanted.stream()
                    .filter(accountId -> !projected.contains(accountId))
                    .forEach(accountId -> turmsAdmin.addGroupMember(turmsGroupId, accountId));
            projected.stream()
                    .filter(accountId -> !wanted.contains(accountId))
                    .forEach(accountId -> turmsAdmin.removeGroupMember(turmsGroupId, accountId));

            markSynced(roomId);
        } catch (ApiException e) {
            // 投影失败不回滚业务写：留在 pending，重放器下一轮按 PG 重算（§4 的 S3 边界）
            log.warn("群投影失败，留在 pending：roomId={}", roomId, e);
        }
    }

    /** 定时扫一遍 pending：间隔是 `moonchat.turms.replay-interval`（30 秒，未确认）。 */
    @Override
    @Scheduled(fixedDelayString = "${moonchat.turms.replay-interval}")
    public void replayPending() {
        Set<Long> pendingRoomIds = new HashSet<>();
        roomInfoMapper.selectList(new LambdaQueryWrapper<RoomInfo>()
                        .eq(RoomInfo::getTurmsSyncState, TurmsSyncState.PENDING))
                .forEach(room -> pendingRoomIds.add(room.getId()));
        if (pendingRoomIds.isEmpty()) {
            return;
        }
        log.info("重放群投影：{} 个 pending", pendingRoomIds.size());
        pendingRoomIds.forEach(this::reconcile);
    }

    /** Turms 那边没有这个群（从没建过，或者被丢了）：重建立刻回填 group id，否则成员无处可投影。 */
    private long createGroup(RoomInfo room) {
        Long turmsGroupId = turmsAdmin.createGroup(room.getOwnerAccountId(), room.getName());
        roomInfoMapper.update(null, new LambdaUpdateWrapper<RoomInfo>()
                .eq(RoomInfo::getId, room.getId())
                .set(RoomInfo::getTurmsGroupId, turmsGroupId)
                .set(RoomInfo::getUpdatedAt, OffsetDateTime.now()));
        return turmsGroupId;
    }

    /** 投影只读 `room_member`：`account_room` 是查询镜像，不参与投影。 */
    private Set<Long> validMemberIds(long roomId) {
        Set<Long> accountIds = new HashSet<>();
        roomMemberMapper.selectList(new LambdaQueryWrapper<RoomMember>()
                        .eq(RoomMember::getRoomId, roomId)
                        .isNull(RoomMember::getDeletedAt))
                .forEach(member -> accountIds.add(member.getAccountId()));
        return accountIds;
    }

    private void markSynced(long roomId) {
        roomInfoMapper.update(null, new LambdaUpdateWrapper<RoomInfo>()
                .eq(RoomInfo::getId, roomId)
                .set(RoomInfo::getTurmsSyncState, TurmsSyncState.SYNCED)
                .set(RoomInfo::getUpdatedAt, OffsetDateTime.now()));
    }
}
