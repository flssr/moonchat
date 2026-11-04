package im.moonchat.biz.dto.friendship;

import java.time.Instant;
import java.util.List;

/**
 * #8 #9 #10 的响应体。`requested_by` 不出现，对外只有 `incoming`；
 * `friendship.id` 也不出现——客户端没有理由保存一个不透明 id（docs/api-contracts.md §5）。
 */
public final class FriendshipResponses {

    private FriendshipResponses() {
    }

    public record Item(long peerAccountId, String displayName, String status, boolean incoming,
            Instant requestedAt) {
    }

    public record ListResponse(List<Item> items) {
    }

    public record RequestResponse(long peerAccountId, String status, boolean incoming) {
    }

    public record AcceptResponse(long peerAccountId, String status) {
    }
}
