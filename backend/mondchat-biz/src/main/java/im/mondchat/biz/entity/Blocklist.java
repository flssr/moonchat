package im.mondchat.biz.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * `blocklist` 表：拉黑是业务真相（docs/truth/backend/persistence.md），有向、成对唯一。
 * `ownerAccountId` 是拉黑方，`blockedAccountId` 是被拉黑方；取消拉黑就是删这一行。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("blocklist")
public class Blocklist {

    private Long ownerAccountId;

    private Long blockedAccountId;

    private OffsetDateTime createdAt;
}
