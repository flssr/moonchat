package im.moonchat.biz.auth;

/** 入口凭据认证出的调用方。S1 只有登录 JWT 一种来源，账号密钥随 S2 的建 agent 一起来。 */
public record CurrentAccount(long accountId) {
}
