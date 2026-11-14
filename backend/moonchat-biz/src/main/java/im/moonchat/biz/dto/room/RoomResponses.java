package im.moonchat.biz.dto.room;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;

/**
 * #12–#18 的响应体。`turms_sync_state` 一概不出门：对外的群标识是 `room_id`；唯一例外是
 * `turms_group_id`——它只在 #13 作为投递句柄出现（字符串，避免 JS 精度丢失），写接口只认
 * `room_id`（docs/truth/backend/room.md）。成员列表也没有 `role`——群主就是 `owner_account_id`，
 * 是不是群主由客户端比较这两个 id 得出。
 * `Item` / `ListResponse` 与好友那边同名，文档里靠 `@Schema(name)` 区分。
 */
public final class RoomResponses {

    private RoomResponses() {
    }

    public record CreateResponse(long roomId, String name, long ownerAccountId, Instant createdAt) {
    }

    @Schema(name = "RoomItem")
    public record Item(long roomId, String name, long ownerAccountId, Instant joinedAt, String turmsGroupId) {
    }

    @Schema(name = "RoomListResponse")
    public record ListResponse(List<Item> items) {
    }

    public record InfoResponse(long roomId, String name, long ownerAccountId, long memberCount,
            Instant createdAt) {
    }

    public record MemberItem(long accountId, String displayName, boolean isFriend, Instant joinedAt) {
    }

    /** 唯一分页的接口：群规模没有上限，其余列表 V1 一次返回全量。 */
    public record MembersResponse(List<MemberItem> items, int page, int size, long total) {
    }

    public record MemberResponse(long roomId, long accountId, Instant joinedAt) {
    }
}
