package im.mondchat.biz.service.room.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.dto.room.RoomRequests;
import im.mondchat.biz.dto.room.RoomResponses;
import im.mondchat.biz.entity.AccountInfo;
import im.mondchat.biz.entity.AccountRoom;
import im.mondchat.biz.entity.RoomInfo;
import im.mondchat.biz.entity.RoomMember;
import im.mondchat.biz.entity.TurmsSyncState;
import im.mondchat.biz.mapper.account.AccountInfoMapper;
import im.mondchat.biz.mapper.room.AccountRoomMapper;
import im.mondchat.biz.mapper.room.RoomInfoMapper;
import im.mondchat.biz.mapper.room.RoomMemberMapper;
import im.mondchat.biz.service.friendship.FriendshipService;
import im.mondchat.biz.service.room.RoomService;
import im.mondchat.biz.service.turms.RoomProjectionService;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 群与成员的读写。三张表里 `room_member` 是唯一真相，`account_room` 是同一事务里的查询镜像
 * （一次写入使用同一个应用时间值），`room_info.turms_sync_state` 是投影的待办标记。
 */
@Service
@RequiredArgsConstructor
public class RoomServiceImpl implements RoomService {

    private static final String FROZEN = "frozen";
    private static final String ACCEPTED = "accepted";
    private static final int MAX_PAGE_SIZE = 100;

    private final RoomInfoMapper roomInfoMapper;
    private final RoomMemberMapper roomMemberMapper;
    private final AccountRoomMapper accountRoomMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final FriendshipService friendshipService;
    private final RoomProjectionService projectionService;

    /** 「群主一定是成员」是事务产物：群、群主的成员行、镜像行一次写完，再投影。 */
    @Override
    @Transactional
    public RoomResponses.CreateResponse create(CurrentAccount me, RoomRequests.CreateRequest request) {
        ensureHuman(me);
        ensureNotFrozen(me.accountId());

        OffsetDateTime now = OffsetDateTime.now();
        RoomInfo room = RoomInfo.builder()
                .name(request.name())
                .ownerAccountId(me.accountId())
                .turmsSyncState(TurmsSyncState.PENDING)
                .createdAt(now)
                .updatedAt(now)
                .build();
        roomInfoMapper.insert(room);
        join(room.getId(), me.accountId(), now);
        projectAfterCommit(room.getId());

        return new RoomResponses.CreateResponse(room.getId(), room.getName(), me.accountId(), now.toInstant());
    }

    /** 不读 Turms 的群列表：它的群列表不等于业务列表（Turms 里可能有残留的游离群）。 */
    @Override
    public RoomResponses.ListResponse mine(CurrentAccount me) {
        List<AccountRoom> links = accountRoomMapper.selectList(new LambdaQueryWrapper<AccountRoom>()
                .eq(AccountRoom::getAccountId, me.accountId())
                .isNull(AccountRoom::getDeletedAt)
                .orderByAsc(AccountRoom::getRoomId));
        if (links.isEmpty()) {
            return new RoomResponses.ListResponse(List.of());
        }

        Map<Long, RoomInfo> rooms = roomInfoMapper
                .selectList(new LambdaQueryWrapper<RoomInfo>()
                        .in(RoomInfo::getId, links.stream().map(AccountRoom::getRoomId).toList()))
                .stream()
                .collect(Collectors.toMap(RoomInfo::getId, Function.identity()));
        List<RoomResponses.Item> items = links.stream()
                .map(link -> {
                    RoomInfo room = rooms.get(link.getRoomId());
                    Long turmsGroupId = room.getTurmsGroupId();
                    return new RoomResponses.Item(link.getRoomId(), room.getName(), room.getOwnerAccountId(),
                            link.getJoinedAt().toInstant(),
                            turmsGroupId == null ? null : turmsGroupId.toString());
                })
                .toList();
        return new RoomResponses.ListResponse(items);
    }

    @Override
    public RoomResponses.InfoResponse info(CurrentAccount me, long roomId) {
        RoomInfo room = requireRoom(roomId);
        requireMember(roomId, me.accountId());
        return new RoomResponses.InfoResponse(room.getId(), room.getName(), room.getOwnerAccountId(),
                memberCount(roomId), room.getCreatedAt().toInstant());
    }

    @Override
    public RoomResponses.MembersResponse members(CurrentAccount me, long roomId, int page, int size) {
        if (page < 1) {
            throw ApiException.validationFailed("page", "page 从 1 开始");
        }
        if (size < 1 || size > MAX_PAGE_SIZE) {
            throw ApiException.validationFailed("size", "size 取 1.." + MAX_PAGE_SIZE);
        }
        requireRoom(roomId);
        requireMember(roomId, me.accountId());

        long total = memberCount(roomId);
        List<RoomMember> rows = roomMemberMapper.selectList(new LambdaQueryWrapper<RoomMember>()
                .eq(RoomMember::getRoomId, roomId)
                .isNull(RoomMember::getDeletedAt)
                .orderByAsc(RoomMember::getJoinedAt)
                .orderByAsc(RoomMember::getAccountId)
                .last("limit " + size + " offset " + ((long) (page - 1) * size)));
        Map<Long, String> names = displayNames(rows.stream().map(RoomMember::getAccountId).toList());
        Set<Long> friends = acceptedFriendIds(me.accountId());
        List<RoomResponses.MemberItem> items = rows.stream()
                .map(row -> new RoomResponses.MemberItem(row.getAccountId(), names.get(row.getAccountId()),
                        friends.contains(row.getAccountId()), row.getJoinedAt().toInstant()))
                .toList();
        return new RoomResponses.MembersResponse(items, page, size, total);
    }

    @Override
    @Transactional
    public RoomResponses.MemberResponse addMember(CurrentAccount me, long roomId,
            RoomRequests.AddMemberRequest request) {
        ensureHuman(me);
        ensureNotFrozen(me.accountId());
        requireRoom(roomId);
        if (!isMember(roomId, me.accountId())) {
            throw ApiException.forbidden("你不是这个群的成员");
        }
        long accountId = request.accountId();
        if (accountInfoMapper.selectById(accountId) == null) {
            throw ApiException.notFound("账号不存在");
        }
        RoomMember existing = findMember(roomId, accountId);
        if (existing != null && existing.getDeletedAt() == null) {
            throw ApiException.conflict("这个账号已经在群里");
        }

        OffsetDateTime now = OffsetDateTime.now();
        join(roomId, accountId, now);
        markPending(roomId, now);
        projectAfterCommit(roomId);
        return new RoomResponses.MemberResponse(roomId, accountId, now.toInstant());
    }

    @Override
    @Transactional
    public void leave(CurrentAccount me, long roomId) {
        ensureHuman(me);
        ensureNotFrozen(me.accountId());
        RoomInfo room = requireRoom(roomId);
        if (room.getOwnerAccountId() == me.accountId()) {
            throw ApiException.ownerCannotLeave();
        }
        if (!isMember(roomId, me.accountId())) {
            throw ApiException.notRoomMember();
        }

        OffsetDateTime now = OffsetDateTime.now();
        quit(roomId, me.accountId(), now);
        markPending(roomId, now);
        projectAfterCommit(roomId);
    }

    @Override
    @Transactional
    public void removeMember(CurrentAccount me, long roomId, long accountId) {
        ensureHuman(me);
        ensureNotFrozen(me.accountId());
        RoomInfo room = requireRoom(roomId);
        if (room.getOwnerAccountId() != me.accountId()) {
            throw ApiException.forbidden("只有群主能移除成员");
        }
        if (accountId == room.getOwnerAccountId()) {
            throw ApiException.ownerCannotLeave();
        }
        RoomMember existing = findMember(roomId, accountId);
        if (existing == null || existing.getDeletedAt() != null) {
            throw ApiException.notFound("这个账号不是有效成员");
        }

        OffsetDateTime now = OffsetDateTime.now();
        quit(roomId, accountId, now);
        markPending(roomId, now);
        projectAfterCommit(roomId);
    }

    /**
     * 投影在提交之后跑：事务回滚时 Turms 里不该多出一个 PG 不认的群（投影只有一个方向，PG 为准）。
     * 投影失败不向上抛——业务写已经成立，剩下的是重放器的事。
     */
    private void projectAfterCommit(long roomId) {
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                projectionService.reconcile(roomId);
            }
        });
    }

    /**
     * 入群：没行就插入，purge 前重进就复用原行并刷新加入时间。
     * 两个并发请求可能都读到「无行」：主键兜底，落败方回 409（与 #16 的预查同义）。
     * PG 已经中止了本事务，这里只是把唯一键冲突翻成契约里那个码。
     */
    private void join(long roomId, long accountId, OffsetDateTime now) {
        if (findMember(roomId, accountId) == null) {
            try {
                roomMemberMapper.insert(RoomMember.builder()
                        .roomId(roomId)
                        .accountId(accountId)
                        .joinedAt(now)
                        .build());
                accountRoomMapper.insert(AccountRoom.builder()
                        .accountId(accountId)
                        .roomId(roomId)
                        .joinedAt(now)
                        .build());
            } catch (DuplicateKeyException e) {
                throw ApiException.conflict("这个账号已经在群里");
            }
            return;
        }
        roomMemberMapper.update(null, new LambdaUpdateWrapper<RoomMember>()
                .eq(RoomMember::getRoomId, roomId)
                .eq(RoomMember::getAccountId, accountId)
                .set(RoomMember::getJoinedAt, now)
                .set(RoomMember::getDeletedAt, null));
        accountRoomMapper.update(null, new LambdaUpdateWrapper<AccountRoom>()
                .eq(AccountRoom::getAccountId, accountId)
                .eq(AccountRoom::getRoomId, roomId)
                .set(AccountRoom::getJoinedAt, now)
                .set(AccountRoom::getDeletedAt, null));
    }

    /** 退群与被移除是同一件事：两张成员表同事务写同一个 tombstone 时间。 */
    private void quit(long roomId, long accountId, OffsetDateTime now) {
        roomMemberMapper.update(null, new LambdaUpdateWrapper<RoomMember>()
                .eq(RoomMember::getRoomId, roomId)
                .eq(RoomMember::getAccountId, accountId)
                .set(RoomMember::getDeletedAt, now));
        accountRoomMapper.update(null, new LambdaUpdateWrapper<AccountRoom>()
                .eq(AccountRoom::getAccountId, accountId)
                .eq(AccountRoom::getRoomId, roomId)
                .set(AccountRoom::getDeletedAt, now));
    }

    /** 成员集合变了就是群聚合变了：投影标记回到 pending，投影读的是 `room_member` 全量。 */
    private void markPending(long roomId, OffsetDateTime now) {
        roomInfoMapper.update(null, new LambdaUpdateWrapper<RoomInfo>()
                .eq(RoomInfo::getId, roomId)
                .set(RoomInfo::getTurmsSyncState, TurmsSyncState.PENDING)
                .set(RoomInfo::getUpdatedAt, now));
    }

    private RoomInfo requireRoom(long roomId) {
        RoomInfo room = roomInfoMapper.selectById(roomId);
        if (room == null) {
            throw ApiException.notFound("群不存在");
        }
        return room;
    }

    private void requireMember(long roomId, long accountId) {
        if (!isMember(roomId, accountId)) {
            throw ApiException.notRoomMember();
        }
    }

    /** 授权事实只读 `room_member` 的有效行，不看 `account_room`。 */
    private boolean isMember(long roomId, long accountId) {
        RoomMember member = findMember(roomId, accountId);
        return member != null && member.getDeletedAt() == null;
    }

    private RoomMember findMember(long roomId, long accountId) {
        return roomMemberMapper.selectOne(new LambdaQueryWrapper<RoomMember>()
                .eq(RoomMember::getRoomId, roomId)
                .eq(RoomMember::getAccountId, accountId));
    }

    private long memberCount(long roomId) {
        return roomMemberMapper.selectCount(new LambdaQueryWrapper<RoomMember>()
                .eq(RoomMember::getRoomId, roomId)
                .isNull(RoomMember::getDeletedAt));
    }

    private void ensureHuman(CurrentAccount me) {
        if (me.source() == CurrentAccount.Source.AGENT) {
            throw ApiException.forbidden("群与成员的操作只有真人能做");
        }
    }

    private void ensureNotFrozen(long accountId) {
        if (FROZEN.equals(accountInfoMapper.selectById(accountId).getStatus())) {
            throw ApiException.accountFrozen();
        }
    }

    private Map<Long, String> displayNames(List<Long> accountIds) {
        if (accountIds.isEmpty()) {
            return Map.of();
        }
        return accountInfoMapper.selectList(new LambdaQueryWrapper<AccountInfo>()
                        .in(AccountInfo::getAccountId, accountIds))
                .stream()
                .collect(Collectors.toMap(AccountInfo::getAccountId, AccountInfo::getDisplayName));
    }

    /** 成员列表里的 `is_friend`：一次取到我的好友集合，省掉每行一次查询。 */
    private Set<Long> acceptedFriendIds(long me) {
        return friendshipService.list(new CurrentAccount(me, CurrentAccount.Source.OWNER), ACCEPTED)
                .items()
                .stream()
                .map(item -> item.peerAccountId())
                .collect(Collectors.toSet());
    }
}
