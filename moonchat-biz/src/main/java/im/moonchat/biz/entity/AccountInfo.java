package im.moonchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.Getter;
import lombok.Setter;

/**
 * `account_info` 表：一个账号的名字、状态与唯一认证哈希（docs/biz-data-model.md §4.2）。
 * `credentialHash` 与 `email` 只在本层与持久层之间流转，任何响应都要走 dto 里的白名单字段；
 * 因此这里不开 toString——否则一次 `log.info("{}", info)` 就把哈希打进日志了。
 */
@Getter
@Setter
@TableName("account_info")
public class AccountInfo {

    /** 与 `account.id` 一一对应，由应用写入（不是自增）。 */
    @TableId(value = "account_id", type = IdType.INPUT)
    private Long accountId;

    private String displayName;

    private String status;

    private String email;

    private String credentialHash;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;
}
