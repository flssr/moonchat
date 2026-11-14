package im.mondchat.biz.service.account;

/** agent 账号密钥的认证：明文 → 确定性哈希 → 按 `credential_hash` 反查账号。 */
public interface AccountKeyService {

    /** 查不到账号就回 `unauthenticated`——不区分「密钥错」与「账号不存在」。 */
    long authenticate(String plainKey);
}
