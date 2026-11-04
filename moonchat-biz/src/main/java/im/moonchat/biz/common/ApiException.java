package im.moonchat.biz.common;

import org.springframework.http.HttpStatus;

/**
 * 契约里的失败响应（docs/api-contracts.md §1.3）：code 是客户端唯一该分流的东西，
 * message 给人看，validation_failed 额外带 field。
 */
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

    public static ApiException conflict(String message) {
        return new ApiException("conflict", HttpStatus.CONFLICT, message, null);
    }

    /** im-facade 没从 Turms 拿到确认；注册建用户与发言两处都会用到。 */
    public static ApiException upstreamUnavailable() {
        return new ApiException("upstream_unavailable", HttpStatus.SERVICE_UNAVAILABLE, "Turms 没有确认这次请求", null);
    }

    public String code() {
        return code;
    }

    public HttpStatus status() {
        return status;
    }

    public String field() {
        return field;
    }
}
