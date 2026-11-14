package im.moonchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * `account_room` 表：同一成员关系按账号反向存一份（docs/truth/backend/persistence.md）。
 * 只为「我加入的群」按账号查询；不参与 Turms 投影，也不参与授权。
 *
 * <p>主键是 `(account_id, room_id)`，一律用 Wrapper 读写，不用 `selectById` / `updateById`。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("account_room")
public class AccountRoom {

    @TableId(value = "account_id", type = IdType.INPUT)
    private Long accountId;

    private Long roomId;

    /** `room_member.joined_at` 的镜像，不能独立修改。 */
    private OffsetDateTime joinedAt;

    /** `room_member.deleted_at` 的镜像。 */
    private OffsetDateTime deletedAt;
}
