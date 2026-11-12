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
 * `friendship` 表：好友关系的唯一业务真相（docs/biz-data-model.md §4.3）。
 * `accountId` 恒为规范序里较小的 id，`peerAccountId` 恒为较大的；授权判定只读本表。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("friendship")
public class Friendship {

    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    private Long accountId;

    private Long peerAccountId;

    private String status;

    private Long requestedBy;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;

    /** 空表示有效；非空表示申请被拒或好友已删——拒绝不增加状态枚举值。 */
    private OffsetDateTime deletedAt;
}
