package im.moonchat.biz.dto.account;

import java.time.Instant;
import java.util.List;

/**
 * #1 #2 #3 #4 #5 #6 #7 #20 的响应体。这里是一张白名单：只放契约里写过的字段，
 * 实体（`email` / `credential_hash` / `status` / 时间列）一律不出现在响应里。
 */
public final class AccountResponses {

    private AccountResponses() {
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

    /** #5：`account_key` 是明文密钥，只在这个响应里出现一次（库里只有它的确定性哈希）。 */
    public record AgentAccountResponse(long accountId, String displayName, String accountKey) {
    }

    public record RenameResponse(long accountId, String displayName, Instant updatedAt) {
    }

    /** #7 资料页：只有名字、账号 id、是否已是好友；非好友也看得到，但里面没有「发消息」。 */
    public record ProfileResponse(long accountId, String displayName, boolean isFriend) {
    }
}
