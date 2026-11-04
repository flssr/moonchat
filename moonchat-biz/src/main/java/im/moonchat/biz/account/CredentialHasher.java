package im.moonchat.biz.account;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * 真人密码的哈希：bcrypt（cost 10 起），入库带方案前缀 `bcrypt$`，
 * 所以换算法（例如以后换 Argon2id）不需要改表（docs/biz-data-model.md §4.2）。
 */
@Component
public class CredentialHasher {

    private static final String BCRYPT_PREFIX = "bcrypt$";

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(10);

    public String hashPassword(String rawPassword) {
        // Spring 的输出形如 $2a$10$...，去掉前导 $ 拼上前缀正好是 spec 里的 bcrypt$2a$...
        return BCRYPT_PREFIX + encoder.encode(rawPassword).substring(1);
    }

    public boolean matchesPassword(String rawPassword, String credentialHash) {
        return credentialHash.startsWith(BCRYPT_PREFIX)
                && encoder.matches(rawPassword, "$" + credentialHash.substring(BCRYPT_PREFIX.length()));
    }
}
