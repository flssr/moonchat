package im.moonchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;

/**
 * `account_info` 表：一个账号的名字、状态与唯一认证哈希（docs/biz-data-model.md §4.2）。
 * `credentialHash` 与 `email` 只在本层与持久层之间流转，任何响应都要走 dto 里的白名单字段。
 */
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

    public Long getAccountId() {
        return accountId;
    }

    public void setAccountId(Long accountId) {
        this.accountId = accountId;
    }

    public String getDisplayName() {
        return displayName;
    }

    public void setDisplayName(String displayName) {
        this.displayName = displayName;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getCredentialHash() {
        return credentialHash;
    }

    public void setCredentialHash(String credentialHash) {
        this.credentialHash = credentialHash;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(OffsetDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(OffsetDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
