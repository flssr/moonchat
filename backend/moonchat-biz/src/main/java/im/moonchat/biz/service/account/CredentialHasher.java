package im.moonchat.biz.service.account;

import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.config.AgentProperties;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * `account_info.credential_hash` 的两种算法，都带方案前缀，所以换算法不需要改表
 * （docs/data-model.md §4.2）。
 *
 * <ul>
 *   <li>真人密码：bcrypt（cost 10 起），加盐慢哈希。
 *   <li>agent 账号密钥：确定性 HMAC-SHA256 + pepper，因为 agent 带明文来、必须能反查账号。
 * </ul>
 */
@Component
public class CredentialHasher {

    private static final String BCRYPT_PREFIX = "bcrypt$";
    private static final String HMAC_PREFIX = "hmac-sha256$";
    private static final String HMAC_ALGORITHM = "HmacSHA256";

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(10);
    private final SecretKeySpec pepper;

    public CredentialHasher(AgentProperties properties) {
        this.pepper = new SecretKeySpec(properties.keyPepper().getBytes(StandardCharsets.UTF_8), HMAC_ALGORITHM);
    }

    public String hashPassword(String rawPassword) {
        // Spring 的输出形如 $2a$10$...，去掉前导 $ 拼上前缀正好是 spec 里的 bcrypt$2a$...
        return BCRYPT_PREFIX + encoder.encode(rawPassword).substring(1);
    }

    public boolean matchesPassword(String rawPassword, String credentialHash) {
        return credentialHash.startsWith(BCRYPT_PREFIX)
                && encoder.matches(rawPassword, "$" + credentialHash.substring(BCRYPT_PREFIX.length()));
    }

    /** 确定性哈希：同一个明文密钥永远算出同一串，才能按 `unique (credential_hash)` 反查账号。 */
    public String hashAccountKey(String plainKey) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(pepper);
            byte[] digest = mac.doFinal(plainKey.getBytes(StandardCharsets.UTF_8));
            return HMAC_PREFIX + HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException | InvalidKeyException e) {
            throw new IllegalStateException("算不出 agent 密钥的确定性哈希", e);
        }
    }
}
