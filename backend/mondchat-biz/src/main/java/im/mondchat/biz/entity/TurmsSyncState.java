package im.mondchat.biz.entity;

import com.baomidou.mybatisplus.annotation.EnumValue;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * `account.turms_sync_state` 与 `room_info.turms_sync_state` 的两个取值
 * （docs/truth/backend/persistence.md）：只标记「PG 这一行有没有同步进 Turms」，不是业务状态。
 */
@Getter
@RequiredArgsConstructor
public enum TurmsSyncState {

    /** 待投影：重放器按 PG 重算。 */
    PENDING("pending"),

    /** 已同步：Turms 已确认。 */
    SYNCED("synced");

    /** 落库值，与 DDL 的 check 约束一致。 */
    @EnumValue
    private final String code;
}
