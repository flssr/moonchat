package im.moonchat.biz.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * `moonchat.agent.*`：agent 账号密钥的 HMAC pepper。
 * 与登录 JWT 密钥、Turms 共享密钥都是独立的三把secret（docs/truth/backend/persistence.md）。
 */
@ConfigurationProperties("moonchat.agent")
public record AgentProperties(String keyPepper) {
}
