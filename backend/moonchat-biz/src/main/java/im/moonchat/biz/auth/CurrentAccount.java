package im.moonchat.biz.auth;

/**
 * 入口凭据认证出的调用方。来源由凭据形态决定（docs/truth/backend/identity.md）：
 * 登录 JWT → `owner`，账号密钥 → `agent`；它只用于「仅真人」判定与限流，不作其它权限判断。
 */
public record CurrentAccount(long accountId, Source source) {

    public enum Source {
        OWNER,
        AGENT
    }
}
