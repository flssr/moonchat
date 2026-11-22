package im.mondchat.biz.service.turms;

import java.time.Instant;

/**
 * im-facade 的签发那一支手：给客户端签 Turms 能验的 JWT。
 * 用与 turms-gateway 共享的 HMAC 密钥签，payload 见 docs/truth/backend/identity.md。
 */
public interface TurmsCredentialService {

    /**
     * @param frozen 账号是否已冻结：开关打开时按它选两套 statements 之一（冻结只读 + 清角标）；
     *               开关关闭时该参数不影响结果（只签 `QUERY`）。
     */
    Credential sign(long accountId, boolean frozen);

    record Credential(String token, Instant expiresAt) {
    }
}
