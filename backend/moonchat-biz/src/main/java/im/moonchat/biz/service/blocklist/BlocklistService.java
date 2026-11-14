package im.moonchat.biz.service.blocklist;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.blocklist.BlocklistRequests;
import im.moonchat.biz.dto.blocklist.BlocklistResponses;

/** 黑名单的行为（docs/DDD.md「黑名单」）：看自己的列表、拉黑、取消拉黑与「这个方向是否被拉黑」。 */
public interface BlocklistService {

    /** #21 我的黑名单：`created_at` 倒序分页，`page` / `size` / `total` 与群成员列表同构。 */
    BlocklistResponses.ListResponse list(CurrentAccount me, int page, int size);

    /** #22 拉黑：只写 `blocklist` 一行，不动 `friendship`。 */
    BlocklistResponses.Item block(CurrentAccount me, BlocklistRequests.CreateRequest request);

    /** #23 取消拉黑：物理删行，不在黑名单里就是 `not_found`。 */
    void unblock(CurrentAccount me, long accountId);

    /** 授权事实：`ownerAccountId` 是否拉黑了 `blockedAccountId`——第一个参数是拉黑方。 */
    boolean hasBlocked(long ownerAccountId, long blockedAccountId);
}
