package im.mondchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * `room_member` 表：群成员关系的唯一业务真相（docs/truth/backend/persistence.md）。
 * 成员列表与发送授权都读本表，`account_room` 不能用于授权。
 *
 * <p>主键是 `(room_id, account_id)`，所以 `roomId` 只是 MyBatis-Plus 需要的 `@TableId` 占位——
 * 这里一律用 Wrapper 读写，不用 `selectById` / `updateById`。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("room_member")
public class RoomMember {

    @TableId(value = "room_id", type = IdType.INPUT)
    private Long roomId;

    private Long accountId;

    /** 最近一次加入时间；不参与任何判定。 */
    private OffsetDateTime joinedAt;

    /** 空表示当前成员；非空表示已退群或被移除。 */
    private OffsetDateTime deletedAt;
}
