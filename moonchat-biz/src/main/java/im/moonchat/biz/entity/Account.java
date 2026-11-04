package im.moonchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;

/** `account` 表：身份与归属（docs/biz-data-model.md §4.1）。不存资料，也不参与授权判定。 */
@TableName("account")
public class Account {

    /** 由库里的 identity 生成；它就是 Turms 用户 id。 */
    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    private String type;

    private Long ownerAccountId;

    private String turmsSyncState;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public Long getOwnerAccountId() {
        return ownerAccountId;
    }

    public void setOwnerAccountId(Long ownerAccountId) {
        this.ownerAccountId = ownerAccountId;
    }

    public String getTurmsSyncState() {
        return turmsSyncState;
    }

    public void setTurmsSyncState(String turmsSyncState) {
        this.turmsSyncState = turmsSyncState;
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
