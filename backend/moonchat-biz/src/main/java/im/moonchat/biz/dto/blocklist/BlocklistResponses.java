package im.moonchat.biz.dto.blocklist;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;

/**
 * #21 #22 的响应体。`display_name` 现查 `account_info`，不回显黑名单之外的东西
 * （docs/api-contracts.md §7.1）。`Item` / `ListResponse` 与好友、群那边同名，文档里靠 `@Schema(name)` 区分。
 */
public final class BlocklistResponses {

    private BlocklistResponses() {
    }

    @Schema(name = "BlocklistItem")
    public record Item(long accountId, String displayName, Instant createdAt) {
    }

    /** 分页与群成员列表同构：`page` / `size` / `total`（docs/api-contracts.md §7.1）。 */
    @Schema(name = "BlocklistListResponse")
    public record ListResponse(List<Item> items, int page, int size, long total) {
    }
}
