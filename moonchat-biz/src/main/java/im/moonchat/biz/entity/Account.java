package im.moonchat.biz.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import java.time.OffsetDateTime;
import lombok.Getter;
import lombok.Setter;

/**
 * `account` 表：身份与归属（docs/biz-data-model.md §4.1）。不存资料，也不参与授权判定。
 * 只开 getter/setter：不生成 toString/equals，免得实体被顺手打进日志。
 */
@Getter
@Setter
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
}
