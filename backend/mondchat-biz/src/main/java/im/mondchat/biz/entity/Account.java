package im.mondchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/** `account` 表：身份与归属（docs/truth/backend/persistence.md）。不存资料，也不参与授权判定。 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("account")
public class Account {

    /** 由库里的 identity 生成；它就是 Turms 用户 id。 */
    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    private String type;

    private Long ownerAccountId;

    private TurmsSyncState turmsSyncState;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;
}
