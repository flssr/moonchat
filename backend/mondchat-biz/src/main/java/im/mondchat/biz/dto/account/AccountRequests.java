package im.mondchat.biz.dto.account;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.Locale;

/**
 * #1 #2 #3 #5 #6 的请求体，校验规则见 docs/truth/backend/identity.md。
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

    /** #5 建 agent、#6 改名：两条路由的请求体是同一个东西（只有一个名字）。 */
    public record DisplayNameRequest(
            @NotBlank(message = "名字不能为空")
            @Size(max = 20, message = "名字最长 20 字符")
            String displayName) {

        public DisplayNameRequest {
            displayName = displayName == null ? null : displayName.trim();
        }
    }

    /**
     * #6 改资料：路由是 `PUT`，按**全量提交**语义——三个字段全部必传，不是部分更新。
     * `birthday` 用字符串 + 正则接，非法格式才会把 `field` 指回 `birthday`（直接 `LocalDate` 会走通用 400）；
     * 日历上不存在的日期（`2026-02-31`）由 service 严格解析时报 400。
     */
    public record UpdateProfileRequest(
            @NotBlank(message = "名字不能为空")
            @Size(max = 20, message = "名字最长 20 字符")
            String displayName,

            @NotBlank(message = "gender 不能为空")
            @Pattern(regexp = "male|female|other|private",
                    message = "gender 只能是 male / female / other / private")
            String gender,

            @Pattern(regexp = "^\\d{4}-\\d{2}-\\d{2}$", message = "birthday 形如 YYYY-MM-DD")
            String birthday) {

        public UpdateProfileRequest {
            displayName = displayName == null ? null : displayName.trim();
        }
    }

    /**
     * 改头像：`PUT /api/accounts/me/avatar`，整枚替换语义——`null` 就是清回客户端生成的首字头像。
     *
     * <p>正则只挡「不在平台这一套 key 里」的形状；「真人只能选真人那 6 个、agent 只能选 agent 那 3 个」
     * 要按 `account.type` 判，放在 service（docs/truth/backend/identity.md）。
     */
    public record AvatarRequest(
            @Pattern(regexp = "female_0[1-3]|male_0[1-3]|agent_(blue|pink|gold)",
                    message = "avatar 只能是平台默认头像 key")
            String avatar) {
    }

    private static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase(Locale.ROOT);
    }
}
