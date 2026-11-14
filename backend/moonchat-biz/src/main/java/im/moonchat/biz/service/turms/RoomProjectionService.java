package im.moonchat.biz.service.turms;

/**
 * 群与成员的投影（docs/truth/backend/room.md）：以 PG 为准做 full reconcile，
 * 不做事件流、不做增量补丁。投影只有一个方向，Turms 里没被 PG 记过的群平台视为不存在。
 */
public interface RoomProjectionService {

    /**
     * 按 PG 重算一个群的 Turms 投影：群不在 Turms 就建（回填 `turms_group_id`），成员集合做差集增删。
     * **失败不向上抛**——`docs/truth/backend/room.md` 的 201 只表示「PG 里群已成立」，
     * 投影失败留在 `pending`，由重放器收敛。
     */
    void reconcile(long roomId);

    /** 重放：把所有 `turms_sync_state = 'pending'` 的群重算一遍。V1 单实例，不做互斥。 */
    void replayPending();
}
