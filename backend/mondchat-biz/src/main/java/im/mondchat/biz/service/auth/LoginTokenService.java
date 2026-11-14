package im.mondchat.biz.service.auth;

import java.time.Instant;

/**
 * 登录 JWT 的签与验：只对 Biz 有效（认作 `owner` 来源），与 Turms 凭据是两份东西。
 * 无状态——不写 PG、不存凭据记录；续期就是从「现在」重算 7 天（docs/truth/backend/identity.md）。
 */
public interface LoginTokenService {

    Issued issue(long accountId);

    /** 验签 + 未过期，取出 account_id；任何一处不合格都只回 unauthenticated。 */
    long verify(String token);

    record Issued(String token, Instant expiresAt) {
    }
}
