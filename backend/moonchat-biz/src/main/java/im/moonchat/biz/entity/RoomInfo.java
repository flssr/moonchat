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
 * `room_info` 表：群与群主（docs/data-model.md §4.5）。`id` 就是对外的 `room_id`，
 * `turms_group_id` 只是投递句柄，永不出现在响应里。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("room_info")
public class RoomInfo {

    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    private String name;

    /** 群主；V1 没有转让与解散，所以它永远指向一个有效成员。 */
    private Long ownerAccountId;

    /** Turms 生成的群 id，建群投影成功前为空。 */
    private Long turmsGroupId;

    /** `pending` / `synced`：成员或群资料变化后回到 `pending`，重放器按 PG 重算。 */
    private TurmsSyncState turmsSyncState;

    private OffsetDateTime createdAt;

    private OffsetDateTime updatedAt;
}
