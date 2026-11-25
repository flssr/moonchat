package im.mondchat.turms.plugin.ratelimit;

import org.springframework.boot.context.properties.ConfigurationProperties;
import im.turms.server.common.infra.property.env.common.BaseRateLimitingProperties;

/**
 * 会话级桶：`turms-plugin.mondchat-ratelimit.conversation.*`。
 * 默认四元组 {@code 20/20/1/3000}（容量/初始令牌/每周期补充/补充间隔毫秒），
 * 即初始可发 20 条，之后每 3 秒补 1 个（平均 20 条/分钟）。
 */
@ConfigurationProperties("turms-plugin.mondchat-ratelimit.conversation")
public class ConversationRateLimitProperties extends BaseRateLimitingProperties {

    public ConversationRateLimitProperties() {
        setCapacity(20);
        setInitialTokens(20);
        setTokensPerPeriod(1);
        setRefillIntervalMillis(3_000);
    }
}
