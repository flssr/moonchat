package im.moonchat.biz.dto.friendship;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/** #9 #10 的请求体，校验规则见 docs/truth/backend/friendship.md。接口面只用对端账号 id 寻址。 */
public final class FriendshipRequests {

    private FriendshipRequests() {
    }

    /** 与 `RoomRequests.CreateRequest` 同名，文档里靠 `@Schema(name)` 区分。 */
    @Schema(name = "FriendshipCreateRequest")
    public record CreateRequest(@NotNull(message = "peer_account_id 不能为空") Long peerAccountId) {
    }

    /** 同意还是拒绝要靠 `action` 表达：这一处是 HTTP 方法表达不了动作的例外之一（§1.1）。 */
    public record RespondRequest(
            @NotBlank(message = "action 不能为空")
            @Pattern(regexp = "accept|reject", message = "action 只能是 accept 或 reject")
            String action) {
    }
}
