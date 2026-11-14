package im.moonchat.biz.dto.blocklist;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;

/** #22 的请求体，字段与错误码见 docs/api-contracts.md §7.2。 */
public final class BlocklistRequests {

    private BlocklistRequests() {
    }

    /** 与 `FriendshipRequests.CreateRequest` 同名，文档里靠 `@Schema(name)` 区分。 */
    @Schema(name = "BlocklistCreateRequest")
    public record CreateRequest(@NotNull(message = "account_id 不能为空") Long accountId) {
    }
}
