package im.moonchat.biz.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * `moonchat.limit.*`：只作用于 `agent` 来源的限流桶速率，写进配置而不是硬编码
 * （docs/agent-connection.md 的「限流与来源」）。两个跨度都是暂定值：账号级 60、会话级 20。
 */
@ConfigurationProperties("moonchat.limit")
public record LimitProperties(int accountPerMinute, int conversationPerMinute) {
}
