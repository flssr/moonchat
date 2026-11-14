package im.moonchat.biz.service.blocklist.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.dto.blocklist.BlocklistRequests;
import im.moonchat.biz.dto.blocklist.BlocklistResponses;
import im.moonchat.biz.entity.AccountInfo;
import im.moonchat.biz.entity.Blocklist;
import im.moonchat.biz.mapper.account.AccountInfoMapper;
import im.moonchat.biz.mapper.blocklist.BlocklistMapper;
import im.moonchat.biz.service.blocklist.BlocklistService;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;

/**
 * 黑名单的读写。这是一条**单向**关系：只断「被拉黑方 → 拉黑方」（docs/DDD.md「黑名单」），
 * 拉黑不解除好友关系，也不进 Turms。两条只能由应用层守的规则：不能拉黑自己、只有真人能做。
 */
@Service
@RequiredArgsConstructor
public class BlocklistServiceImpl implements BlocklistService {

    private static final String FROZEN = "frozen";

    /** 与群成员列表同一个上限：`size` 最多 100。 */
    private static final int MAX_PAGE_SIZE = 100;

    /** 每人最多拉黑 100 人，应用层守（表上表达不了「每个 owner 的行数上限」）。 */
    private static final int BLOCKLIST_LIMIT = 100;

    private final BlocklistMapper blocklistMapper;
    private final AccountInfoMapper accountInfoMapper;

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
    public BlocklistResponses.Item block(CurrentAccount me, BlocklistRequests.CreateRequest request) {
        ensureHuman(me);
        ensureNotFrozen(me.accountId());
        long ownerId = me.accountId();
        long targetId = request.accountId();
        if (ownerId == targetId) {
            throw ApiException.validationFailed("account_id", "不能拉黑自己");
        }
        AccountInfo target = accountInfoMapper.selectById(targetId);
        if (target == null) {
            throw ApiException.notFound("账号不存在");
        }
        // 每人最多拉黑 100 人：并发下 99→100 时可能多进一条，可容忍（docs/data-model.md §5）
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
        return new BlocklistResponses.Item(targetId, target.getDisplayName(), now.toInstant());
    }

    @Override
    public void unblock(CurrentAccount me, long accountId) {
        ensureHuman(me);
        ensureNotFrozen(me.accountId());
        int deleted = blocklistMapper.delete(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, me.accountId())
                .eq(Blocklist::getBlockedAccountId, accountId));
        if (deleted == 0) {
            throw ApiException.notFound("这个人不在你的黑名单里");
        }
    }

    @Override
    public boolean hasBlocked(long ownerAccountId, long blockedAccountId) {
        return blocklistMapper.selectCount(new LambdaQueryWrapper<Blocklist>()
                .eq(Blocklist::getOwnerAccountId, ownerAccountId)
                .eq(Blocklist::getBlockedAccountId, blockedAccountId)) > 0;
    }

    /** 关系动作只有真人能做：agent 连好友申请都只限这一个动作，拉黑更不在它能力内。 */
    private void ensureHuman(CurrentAccount me) {
        if (me.source() == CurrentAccount.Source.AGENT) {
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
