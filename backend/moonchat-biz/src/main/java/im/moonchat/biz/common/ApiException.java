package im.moonchat.biz.common;

import lombok.Getter;
import org.springframework.http.HttpStatus;

/**
 * 契约里的失败响应（docs/api-contracts.md §1.3）：code 是客户端唯一该分流的东西，
 * message 给人看，validation_failed 额外带 field。
 */
@Getter
public class ApiException extends RuntimeException {

    private final String code;
    private final HttpStatus status;
    private final String field;

    private ApiException(String code, HttpStatus status, String message, String field) {
        super(message);
        this.code = code;
        this.status = status;
        this.field = field;
    }

    public static ApiException validationFailed(String field, String message) {
        return new ApiException("validation_failed", HttpStatus.BAD_REQUEST, message, field);
    }

    public static ApiException unauthenticated() {
        return new ApiException("unauthenticated", HttpStatus.UNAUTHORIZED, "凭据缺失或无效", null);
    }

    public static ApiException forbidden(String message) {
        return new ApiException("forbidden", HttpStatus.FORBIDDEN, message, null);
    }

    public static ApiException accountFrozen() {
        return new ApiException("account_frozen", HttpStatus.FORBIDDEN, "账号已冻结", null);
    }

    public static ApiException notFound(String message) {
        return new ApiException("not_found", HttpStatus.NOT_FOUND, message, null);
    }

    /** `dm` 会话的对端不是已成立的好友：好友校验只在写入网关（docs/DDD.md）。 */
    public static ApiException notFriend() {
        return new ApiException("not_friend", HttpStatus.FORBIDDEN, "只有好友之间才能私聊", null);
    }

    /** 对方把你拉黑了：私聊发送与好友申请都拿这个码，客户端要能跟 `forbidden` 区分。 */
    public static ApiException blocked() {
        return new ApiException("blocked", HttpStatus.FORBIDDEN, "对方已拒收你的消息或申请", null);
    }

    /** 黑名单已满 100 人：与「已经在黑名单里」同是 409，客户端按 code 区分两种提示。 */
    public static ApiException blocklistFull() {
        return new ApiException("blocklist_full", HttpStatus.CONFLICT, "黑名单最多 100 人", null);
    }

    /** 调用者不是该群的有效成员：授权事实现查 `room_member`，不看投影。 */
    public static ApiException notRoomMember() {
        return new ApiException("not_room_member", HttpStatus.FORBIDDEN, "你不是这个群的成员", null);
    }

    /** 群主退群或移除自己：V1 没有转让，也没有解散群。 */
    public static ApiException ownerCannotLeave() {
        return new ApiException("owner_cannot_leave", HttpStatus.CONFLICT, "群主不能退群，V1 也不能转让群", null);
    }

    public static ApiException conflict(String message) {
        return new ApiException("conflict", HttpStatus.CONFLICT, message, null);
    }

    /** im-facade 没从 Turms 拿到确认；注册建用户与发言两处都会用到。 */
    public static ApiException upstreamUnavailable() {
        return new ApiException("upstream_unavailable", HttpStatus.SERVICE_UNAVAILABLE, "Turms 没有确认这次请求", null);
    }

    /** 只对 `agent` 来源的账号级限流桶（好友申请）；会话级桶随 S4 的写入网关。 */
    public static ApiException rateLimited() {
        return new ApiException("rate_limited", HttpStatus.TOO_MANY_REQUESTS, "请求太频繁，稍后再试", null);
    }
}
