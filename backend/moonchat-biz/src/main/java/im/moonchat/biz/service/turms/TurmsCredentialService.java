package im.moonchat.biz.service.turms;

import java.time.Instant;

/**
 * im-facade 的签发那一支手：给客户端签 Turms 能验的 JWT。
 * 用与 turms-gateway 共享的 HMAC 密钥签，payload 见 docs/truth/backend/identity.md。
 */
public interface TurmsCredentialService {

    Credential sign(long accountId);

    record Credential(String token, Instant expiresAt) {
    }
}
