package im.moonchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.ToString;

/**
 * `account_info` 表：一个账号的名字、状态与唯一认证哈希（docs/truth/backend/persistence.md）。
 * `credentialHash` 与 `email` 只在本层与持久层之间流转，任何响应都要走 dto 里的白名单字段；
 * `@Data` 生成的 toString 会把哈希带出去，所以在那一列上单独排掉。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("account_info")
public class AccountInfo {

    /** 与 `account.id` 一一对应，由应用写入（不是自增）。 */
    @TableId(value = "account_id", type = IdType.INPUT)
    private Long accountId;

    private String displayName;

    private String status;

    private String email;

    @ToString.Exclude
    private String credentialHash;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;
}
