package im.mondchat.biz.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * `mondchat.limit.*`：Biz 旧 REST 路径的限流桶速率，以及注销入口的确认限流。
 * 两个消息桶只作用于 `agent` 来源；注销桶按账号计数，与来源无关。
 */
@ConfigurationProperties("mondchat.limit")
public record LimitProperties(int accountPerMinute, int conversationPerMinute,
        int accountDeletionPerMinute) {
}
