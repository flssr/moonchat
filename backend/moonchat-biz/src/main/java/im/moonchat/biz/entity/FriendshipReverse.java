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
 * `friendship_reverse` 表：同一好友关系按较大账号 id 反向存一份（docs/biz-data-model.md §4.4）。
 * 可重建的查询镜像，与主表同事务双写；不参与授权判断。
 *
 * <p>主键是 `(account_id, peer_account_id)`，所以 `accountId` 只是 MyBatis-Plus 需要一个
 * `@TableId` 的占位——这里一律用 Wrapper 读写，不用 `selectById` / `updateById`。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("friendship_reverse")
public class FriendshipReverse {

    @TableId(value = "account_id", type = IdType.INPUT)
    private Long accountId;

    private Long peerAccountId;

    private Long friendshipId;

    private String status;

    private Long requestedBy;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;

    private OffsetDateTime deletedAt;
}
