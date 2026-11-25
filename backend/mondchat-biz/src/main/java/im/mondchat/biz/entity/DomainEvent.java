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
 * `domain_event` 表：PG → Turms 投影的唯一通道（docs/truth/backend/projection.md）。
 * `payload` 存的是「该聚合的目标状态」，重复投递收敛到同一结果。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("domain_event")
public class DomainEvent {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String aggregateType;

    private String aggregateId;

    private String eventType;

    /** jsonb 原文：读出来交给派发器按事件类型解析，Biz 不存第二份业务状态。 */
    private String payload;

    private OffsetDateTime createdAt;

    private OffsetDateTime processedAt;

    private Integer attemptCount;

    private OffsetDateTime nextAttemptAt;

    private String lastError;
}
