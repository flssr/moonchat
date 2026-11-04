package im.moonchat.biz.service.friendship;

/** 好友关系的行为（docs/friends.md）：申请、应答、删除与「是不是好友」这一个授权事实。 */
public interface FriendshipService {

    /** 授权事实：`accepted` 且未写 tombstone。一律规范序后读主表 `friendship`，看到反向表。 */
    boolean areFriends(long one, long another);
}
