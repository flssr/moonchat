package im.moonchat.biz.service.room;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.room.RoomRequests;
import im.moonchat.biz.dto.room.RoomResponses;

/**
 * 群与成员的行为（docs/messaging-and-tunnel.md、docs/api-contracts.md §6）：群与成员的真相在 PG，
 * Turms 里的群与成员只是投影。成员操作只有真人能做，`agent` 来源在这四条写接口上一律 403。
 */
public interface RoomService {

    /** #12 建群：一个事务写群、群主的成员行与镜像行，然后投影。 */
    RoomResponses.CreateResponse create(CurrentAccount me, RoomRequests.CreateRequest request);

    /** #13 我加入的群：读 `account_room`，不读 Turms 的群列表。 */
    RoomResponses.ListResponse mine(CurrentAccount me);

    /** #14 群信息：须是有效成员。 */
    RoomResponses.InfoResponse info(CurrentAccount me, long roomId);

    /** #15 群成员列表：唯一分页的接口。 */
    RoomResponses.MembersResponse members(CurrentAccount me, long roomId, int page, int size);

    /** #16 拉人进群：邀请即入群，不设审批，也不要求目标是好友。 */
    RoomResponses.MemberResponse addMember(CurrentAccount me, long roomId, RoomRequests.AddMemberRequest request);

    /** #17 退群：群主退不了（V1 没有转让，也没有解散）。 */
    void leave(CurrentAccount me, long roomId);

    /** #18 移除成员：只有群主能做，也移不掉自己。 */
    void removeMember(CurrentAccount me, long roomId, long accountId);
}
