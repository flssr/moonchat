package im.moonchat.biz.dto.account;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.Locale;

/**
 * #1 #2 #3 的请求体，校验规则见 docs/api-contracts.md §3。
 * 入口校验只在这里做一次，之后靠类型系统流转。
 */
public final class AccountRequests {

    private AccountRequests() {
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

    private static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase(Locale.ROOT);
    }
}
