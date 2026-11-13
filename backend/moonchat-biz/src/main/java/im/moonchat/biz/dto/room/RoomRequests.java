package im.moonchat.biz.dto.room;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** #12 #16 的请求体，校验规则见 docs/api-contracts.md §6。 */
public final class RoomRequests {

    private RoomRequests() {
    }

    /** 群名 20 是我们自己定的（与账号名字对齐），Turms 侧没有这个配置。 */
    @Schema(name = "RoomCreateRequest")
    public record CreateRequest(
            @NotBlank(message = "群名不能为空")
            @Size(max = 20, message = "群名最长 20 字符")
            String name) {

        public CreateRequest {
            name = name == null ? null : name.trim();
        }
    }

    /** 一次一个，不做批量。 */
    public record AddMemberRequest(@NotNull(message = "account_id 不能为空") Long accountId) {
    }
}
