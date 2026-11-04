package im.moonchat.biz.service.friendship.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.dto.friendship.FriendshipRequests;
import im.moonchat.biz.dto.friendship.FriendshipResponses;
import im.moonchat.biz.entity.AccountInfo;
import im.moonchat.biz.entity.Friendship;
import im.moonchat.biz.entity.FriendshipReverse;
import im.moonchat.biz.mapper.account.AccountInfoMapper;
import im.moonchat.biz.mapper.friendship.FriendshipMapper;
import im.moonchat.biz.mapper.friendship.FriendshipReverseMapper;
import im.moonchat.biz.service.friendship.FriendshipService;
import im.moonchat.biz.service.limiter.AccountRateLimiter;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 好友关系的读写。三条只能由应用层守的规则在这里：
 * 规范序（小 id 在前）、两张表同事务双写（同一个应用时间值）、拒绝写 tombstone 而不是新增状态值。
 */
@Service
@RequiredArgsConstructor
public class FriendshipServiceImpl implements FriendshipService {

    private static final String PENDING = "pending";
    private static final String ACCEPTED = "accepted";
    private static final String FROZEN = "frozen";

    private final FriendshipMapper friendshipMapper;
    private final FriendshipReverseMapper reverseMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final AccountRateLimiter accountRateLimiter;

    @Override
    public FriendshipResponses.ListResponse list(CurrentAccount me, String status) {
        String wanted = status == null ? ACCEPTED : status;
        if (!PENDING.equals(wanted) && !ACCEPTED.equals(wanted)) {
            throw ApiException.validationFailed("status", "status 只能是 pending 或 accepted");
        }

        long meId = me.accountId();
        // 按我在规范序里的位置选表：我是较小的一方查主表，我是较大的一方查反向表。
        List<Row> rows = new ArrayList<>();
        friendshipMapper.selectList(new LambdaQueryWrapper<Friendship>()
                        .eq(Friendship::getAccountId, meId)
                        .eq(Friendship::getStatus, wanted)
                        .isNull(Friendship::getDeletedAt))
                .forEach(row -> rows.add(new Row(row.getPeerAccountId(), row.getRequestedBy(), row.getCreatedAt())));
        reverseMapper.selectList(new LambdaQueryWrapper<FriendshipReverse>()
                        .eq(FriendshipReverse::getAccountId, meId)
                        .eq(FriendshipReverse::getStatus, wanted)
                        .isNull(FriendshipReverse::getDeletedAt))
                .forEach(row -> rows.add(new Row(row.getPeerAccountId(), row.getRequestedBy(), row.getCreatedAt())));

        // 待处理只看「发给我的」：我发出去的那些不在这里
        if (PENDING.equals(wanted)) {
            rows.removeIf(row -> row.requestedBy() == meId);
        }

        Map<Long, String> names = displayNames(rows.stream().map(Row::peerAccountId).toList());
        List<FriendshipResponses.Item> items = rows.stream()
                .map(row -> new FriendshipResponses.Item(row.peerAccountId(), names.get(row.peerAccountId()),
                        wanted, PENDING.equals(wanted), row.requestedAt().toInstant()))
                .toList();
        return new FriendshipResponses.ListResponse(items);
    }

    @Override
    @Transactional
    public FriendshipResponses.RequestResponse request(CurrentAccount me, FriendshipRequests.CreateRequest request) {
        long meId = me.accountId();
        long peerId = request.peerAccountId();
        if (meId == peerId) {
            throw ApiException.validationFailed("peer_account_id", "不能给自己发好友申请");
        }
        AccountInfo peer = accountInfoMapper.selectById(peerId);
        if (peer == null) {
            throw ApiException.notFound("账号不存在");
        }
        if (FROZEN.equals(accountInfoMapper.selectById(meId).getStatus()) || FROZEN.equals(peer.getStatus())) {
            throw ApiException.accountFrozen();
        }

        long lower = Math.min(meId, peerId);
        long higher = Math.max(meId, peerId);
        Friendship existing = findRow(lower, higher);
        if (existing != null && existing.getDeletedAt() == null) {
            throw ApiException.conflict(ACCEPTED.equals(existing.getStatus()) ? "已经是好友" : "已经有待处理的申请");
        }

        // 校验先于桶：429 只落在真正会被处理的申请上，不会盖住 404 / 409
        if (me.source() == CurrentAccount.Source.AGENT) {
            accountRateLimiter.check(meId);
        }

        OffsetDateTime now = OffsetDateTime.now();
        long friendshipId;
        if (existing == null) {
            Friendship row = Friendship.builder()
                    .accountId(lower)
                    .peerAccountId(higher)
                    .status(PENDING)
                    .requestedBy(meId)
                    .createdAt(now)
                    .updatedAt(now)
                    .build();
            friendshipMapper.insert(row);
            friendshipId = row.getId();
            reverseMapper.insert(FriendshipReverse.builder()
                    .accountId(higher)
                    .peerAccountId(lower)
                    .friendshipId(friendshipId)
                    .status(PENDING)
                    .requestedBy(meId)
                    .createdAt(now)
                    .updatedAt(now)
                    .build());
        } else {
            // 被拒绝过或删过：复用原行，不插入第二个同 pair 行
            friendshipId = existing.getId();
            friendshipMapper.update(null, new LambdaUpdateWrapper<Friendship>()
                    .eq(Friendship::getId, friendshipId)
                    .set(Friendship::getStatus, PENDING)
                    .set(Friendship::getRequestedBy, meId)
                    .set(Friendship::getCreatedAt, now)
                    .set(Friendship::getUpdatedAt, now)
                    .set(Friendship::getDeletedAt, null));
            reverseMapper.update(null, new LambdaUpdateWrapper<FriendshipReverse>()
                    .eq(FriendshipReverse::getFriendshipId, friendshipId)
                    .set(FriendshipReverse::getStatus, PENDING)
                    .set(FriendshipReverse::getRequestedBy, meId)
                    .set(FriendshipReverse::getCreatedAt, now)
                    .set(FriendshipReverse::getUpdatedAt, now)
                    .set(FriendshipReverse::getDeletedAt, null));
        }

        return new FriendshipResponses.RequestResponse(peerId, PENDING, false);
    }

    @Override
    @Transactional
    public FriendshipResponses.AcceptResponse accept(CurrentAccount me, long peerAccountId) {
        Friendship row = pendingRowForAnswer(me, peerAccountId);
        markRow(row.getId(), ACCEPTED, OffsetDateTime.now(), false);
        return new FriendshipResponses.AcceptResponse(peerAccountId, ACCEPTED);
    }

    @Override
    @Transactional
    public void reject(CurrentAccount me, long peerAccountId) {
        Friendship row = pendingRowForAnswer(me, peerAccountId);
        markRow(row.getId(), row.getStatus(), OffsetDateTime.now(), true);
    }

    @Override
    @Transactional
    public void delete(CurrentAccount me, long peerAccountId) {
        ensureNotFrozen(me.accountId());
        long lower = Math.min(me.accountId(), peerAccountId);
        long higher = Math.max(me.accountId(), peerAccountId);
        Friendship row = findRow(lower, higher);
        if (row == null || row.getDeletedAt() != null || !ACCEPTED.equals(row.getStatus())) {
            throw ApiException.notFound("没有有效的好友关系");
        }
        markRow(row.getId(), ACCEPTED, OffsetDateTime.now(), true);
    }

    @Override
    public boolean areFriends(long one, long another) {
        long lower = Math.min(one, another);
        long higher = Math.max(one, another);
        return friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getAccountId, lower)
                .eq(Friendship::getPeerAccountId, higher)
                .eq(Friendship::getStatus, ACCEPTED)
                .isNull(Friendship::getDeletedAt)) > 0;
    }

    /** 应答前要过三关：有这条有效申请、不是我发出去的、它还在 `pending`。 */
    private Friendship pendingRowForAnswer(CurrentAccount me, long peerAccountId) {
        ensureNotFrozen(me.accountId());
        Friendship row = findRow(Math.min(me.accountId(), peerAccountId), Math.max(me.accountId(), peerAccountId));
        if (row == null || row.getDeletedAt() != null) {
            throw ApiException.notFound("没有待处理的申请");
        }
        if (row.getRequestedBy() == me.accountId()) {
            throw ApiException.forbidden("这条申请是你发出去的，不能自己应答");
        }
        if (!PENDING.equals(row.getStatus())) {
            throw ApiException.conflict("这条关系已经不是待处理");
        }
        return row;
    }

    /** 两张表同事务写同一个结果：一次写入使用同一个应用时间值。 */
    private void markRow(long friendshipId, String status, OffsetDateTime now, boolean tombstone) {
        friendshipMapper.update(null, new LambdaUpdateWrapper<Friendship>()
                .eq(Friendship::getId, friendshipId)
                .set(Friendship::getStatus, status)
                .set(Friendship::getUpdatedAt, now)
                .set(Friendship::getDeletedAt, tombstone ? now : null));
        reverseMapper.update(null, new LambdaUpdateWrapper<FriendshipReverse>()
                .eq(FriendshipReverse::getFriendshipId, friendshipId)
                .set(FriendshipReverse::getStatus, status)
                .set(FriendshipReverse::getUpdatedAt, now)
                .set(FriendshipReverse::getDeletedAt, tombstone ? now : null));
    }

    private Friendship findRow(long lower, long higher) {
        return friendshipMapper.selectOne(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getAccountId, lower)
                .eq(Friendship::getPeerAccountId, higher));
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

    /** 两侧表取出来后摊平成同一个形状：对端、谁发起的、什么时候。 */
    private record Row(long peerAccountId, long requestedBy, OffsetDateTime requestedAt) {
    }
}
