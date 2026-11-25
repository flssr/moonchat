package im.mondchat.biz.service.blocklist.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.dto.blocklist.BlocklistRequests;
import im.mondchat.biz.dto.blocklist.BlocklistResponses;
import im.mondchat.biz.entity.Account;
import im.mondchat.biz.entity.AccountInfo;
import im.mondchat.biz.entity.Blocklist;
import im.mondchat.biz.entity.Friendship;
import im.mondchat.biz.mapper.account.AccountInfoMapper;
import im.mondchat.biz.mapper.blocklist.BlocklistMapper;
import im.mondchat.biz.mapper.friendship.FriendshipMapper;
import im.mondchat.biz.service.account.AccountLockService;
import im.mondchat.biz.service.blocklist.BlocklistService;
import im.mondchat.biz.service.projection.ProjectionEvents;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 黑名单的读写。这是一条**单向**关系：只断「被拉黑方 → 拉黑方」（docs/truth/backend/friendship.md），
 * 拉黑不解除好友关系，也不进 Turms。两条只能由应用层守的规则：不能拉黑自己、只有真人能做。
 */
@Service
@RequiredArgsConstructor
public class BlocklistServiceImpl implements BlocklistService {

    private static final String FROZEN = "frozen";
    private static final String HUMAN = "human";

    /** 与群成员列表同一个上限：`size` 最多 100。 */
    private static final int MAX_PAGE_SIZE = 100;

    /** 每人最多拉黑 100 人，应用层守（表上表达不了「每个 owner 的行数上限」）。 */
    private static final int BLOCKLIST_LIMIT = 100;

    private final BlocklistMapper blocklistMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final AccountLockService accountLocks;
    private final FriendshipMapper friendshipMapper;
    private final ProjectionEvents projectionEvents;

    @Override
    public BlocklistResponses.ListResponse list(CurrentAccount me, int page, int size) {
        if (page < 1) {
            throw ApiException.validationFailed("page", "page 从 1 开始");
        }
        if (size < 1 || size > MAX_PAGE_SIZE) {
            throw ApiException.validationFailed("size", "size 取 1.." + MAX_PAGE_SIZE);
        }
        long ownerId = me.accountId();
        long total = blocklistMapper.selectCount(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, ownerId));
        List<Blocklist> rows = blocklistMapper.selectList(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, ownerId)
                .orderByDesc(Blocklist::getCreatedAt)
                // 批量拉黑是同秒写入：只按时间排,offset 翻页会重复或漏行
                .orderByDesc(Blocklist::getBlockedAccountId)
                .last("limit " + size + " offset " + ((long) (page - 1) * size)));
        Map<Long, String> names = displayNames(rows.stream().map(Blocklist::getBlockedAccountId).toList());
        return new BlocklistResponses.ListResponse(rows.stream()
                .map(row -> new BlocklistResponses.Item(row.getBlockedAccountId(),
                        names.get(row.getBlockedAccountId()), row.getCreatedAt().toInstant()))
                .toList(), page, size, total);
    }

    @Override
    @Transactional
    public BlocklistResponses.Item block(CurrentAccount me, BlocklistRequests.CreateRequest request) {
        long ownerId = me.accountId();
        long targetId = request.accountId();
        if (ownerId == targetId) {
            throw ApiException.validationFailed("account_id", "不能拉黑自己");
        }
        Map<Long, Account> locked = accountLocks.lockAll(List.of(ownerId, targetId));
        ensureHuman(me, locked.get(ownerId));
        ensureNotFrozen(ownerId);
        AccountInfo target = accountInfoMapper.selectById(targetId);
        if (target == null) {
            throw ApiException.notFound("账号不存在");
        }
        // 每人最多拉黑 100 人：并发下 99→100 时可能多进一条，可容忍（docs/truth/backend/persistence.md）
        if (blocklistMapper.selectCount(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, ownerId)) >= BLOCKLIST_LIMIT) {
            throw ApiException.blocklistFull();
        }

        OffsetDateTime now = OffsetDateTime.now();
        // 两条并发拉黑同一个人的时候，落败方撞主键回 409，而不是 500（同 §1.5）
        try {
            blocklistMapper.insert(Blocklist.builder()
                    .ownerAccountId(ownerId)
                    .blockedAccountId(targetId)
                    .createdAt(now)
                    .build());
        } catch (DuplicateKeyException e) {
            throw ApiException.conflict("已经在黑名单里");
        }
        projectionEvents.blocklistChanged(ownerId, targetId, true, areFriends(ownerId, targetId));
        return new BlocklistResponses.Item(targetId, target.getDisplayName(), now.toInstant());
    }

    @Override
    @Transactional
    public void unblock(CurrentAccount me, long accountId) {
        Map<Long, Account> locked = accountLocks.lockAll(List.of(me.accountId(), accountId));
        ensureHuman(me, locked.get(me.accountId()));
        ensureNotFrozen(me.accountId());
        int deleted = blocklistMapper.delete(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, me.accountId())
                .eq(Blocklist::getBlockedAccountId, accountId));
        if (deleted == 0) {
            throw ApiException.notFound("这个人不在你的黑名单里");
        }
        projectionEvents.blocklistChanged(me.accountId(), accountId, false, areFriends(me.accountId(), accountId));
    }

    /** 取消拉黑时要区分「仍是好友」与「不是好友」：前者清 blockDate，后者删行（projection.md）。 */
    private boolean areFriends(long one, long another) {
        long lower = Math.min(one, another);
        long higher = Math.max(one, another);
        return friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getAccountId, lower)
                .eq(Friendship::getPeerAccountId, higher)
                .eq(Friendship::getStatus, "accepted")
                .isNull(Friendship::getDeletedAt)) > 0;
    }

    @Override
    public boolean hasBlocked(long ownerAccountId, long blockedAccountId) {
        return blocklistMapper.selectCount(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, ownerAccountId)
                .eq(Blocklist::getBlockedAccountId, blockedAccountId)) > 0;
    }

    /** 关系动作只有真人能做：agent 连好友申请都只限这一个动作，拉黑更不在它能力内。 */
    private void ensureHuman(CurrentAccount me, Account account) {
        if (me.source() == CurrentAccount.Source.AGENT || !HUMAN.equals(account.getType())) {
            throw ApiException.forbidden("拉黑与取消拉黑只有真人能做");
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
}
