package im.mondchat.biz.service.friendship;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.friendship.FriendshipRequests;
import im.mondchat.biz.dto.friendship.FriendshipResponses;

/** 好友关系的行为（docs/truth/architecture.md）：申请、应答、删除与「是不是好友」这一个授权事实。 */
public interface FriendshipService {

    /** #8 好友列表 / 发给我的待处理申请。 */
    FriendshipResponses.ListResponse list(CurrentAccount me, String status);

    /** #9 发好友申请：两表同事务，申请与成立是同一行的两个状态。 */
    FriendshipResponses.RequestResponse request(CurrentAccount me, FriendshipRequests.CreateRequest request);

    /** #10 同意：只找有效 `pending` 行，且只有被申请方能应答。 */
    FriendshipResponses.AcceptResponse accept(CurrentAccount me, long peerAccountId);

    /** #10 拒绝：写 tombstone，不增加状态枚举值，对方可以再申请。 */
    void reject(CurrentAccount me, long peerAccountId);

    /** #11 删好友：写 tombstone，Turms 侧什么都不发生（会话保留、历史只读）。 */
    void delete(CurrentAccount me, long peerAccountId);

    /** 授权事实：`accepted` 且未写 tombstone。一律规范序后读主表 `friendship`，不看反向表。 */
    boolean areFriends(long one, long another);
}
