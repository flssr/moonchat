package im.mondchat.biz.dto.friendship;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;

/**
 * #8 #9 #10 的响应体。`requested_by` 不出现，对外只有 `incoming`；
 * `friendship.id` 也不出现——客户端没有理由保存一个不透明 id（docs/truth/backend/friendship.md）。
 * `Item` / `ListResponse` 与群那边同名，文档里靠 `@Schema(name)` 区分。
 */
public final class FriendshipResponses {

    private FriendshipResponses() {
    }

    @Schema(name = "FriendshipItem")
    public record Item(long peerAccountId, String displayName, String avatar, String status,
            boolean incoming, Instant requestedAt) {
    }

    @Schema(name = "FriendshipListResponse")
    public record ListResponse(List<Item> items) {
    }

    public record RequestResponse(long peerAccountId, String status, boolean incoming) {
    }

    public record AcceptResponse(long peerAccountId, String status) {
    }
}
