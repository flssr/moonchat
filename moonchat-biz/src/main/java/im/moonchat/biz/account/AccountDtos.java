package im.moonchat.biz.account;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.Locale;

/**
 * #1 #2 #3 #4 #20 的请求与响应体，字段与校验规则见 docs/api-contracts.md §3、§4。
 * 入口校验只在这里做一次，之后靠类型系统流转。
 */
public final class AccountDtos {

    private AccountDtos() {
    }

    public record RegisterRequest(
            @NotBlank(message = "邮箱不能为空")
            @Size(max = 254, message = "邮箱最长 254 字符")
            @Pattern(regexp = "^[^@]+@.+$", message = "邮箱格式不合法")
            String email,

            @NotBlank(message = "密码不能为空")
            @Size(min = 8, max = 72, message = "密码长度 8..72")
            @Pattern(regexp = ".*[^0-9].*", message = "密码不能是纯数字")
            String password,

            @NotBlank(message = "名字不能为空")
            @Size(max = 20, message = "名字最长 20 字符")
            String displayName) {

        /** 邮箱存 trim + 小写后的值（`account_info` 的 check 就要求这样），名字去掉首尾空白。 */
        public RegisterRequest {
            email = normalizeEmail(email);
            displayName = displayName == null ? null : displayName.trim();
        }
    }

    public record LoginRequest(
            @NotBlank(message = "邮箱不能为空") String email,
            @NotBlank(message = "密码不能为空") String password) {

        public LoginRequest {
            email = normalizeEmail(email);
        }
    }

    /** #3 的两种形态恰好一种；"恰好一种" 由服务层判，缺字段要按契约回不同的码。 */
    public record SessionRequest(Long accountId, String accountKey) {
    }

    public record AccountSummary(long accountId, String type, String displayName) {
    }

    public record RegisterResponse(long accountId, String displayName, String type) {
    }

    /** #2 与 #20 的形状一致：token + 过期时间 + 账号回显。 */
    public record TokenResponse(String token, Instant expiresAt, AccountSummary account) {
    }

    public record SessionResponse(long accountId, String displayName, String type, Turms turms, Instant expiresAt) {

        /** `userId` 就是 `account_id`；`credential` 是 Turms 能验的 JWT，客户端当 password 传给 SDK。 */
        public record Turms(long userId, String credential, String gatewayUrl) {
        }
    }

    public record MineResponse(List<AccountSummary> items) {
    }

    private static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase(Locale.ROOT);
    }
}
