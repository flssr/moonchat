package im.mondchat.turms.plugin.ratelimit;

import org.springframework.boot.context.properties.ConfigurationProperties;
import im.turms.server.common.infra.property.env.common.BaseRateLimitingProperties;

/**
 * 账号级桶：`turms-plugin.mondchat-ratelimit.account.*`。
 * 默认四元组 {@code 60/60/1/1000}（容量/初始令牌/每周期补充/补充间隔毫秒），
 * 即初始可发 60 条，之后每秒补 1 个（平均 60 条/分钟）。
 */
@ConfigurationProperties("turms-plugin.mondchat-ratelimit.account")
public class AccountRateLimitProperties extends BaseRateLimitingProperties {

    public AccountRateLimitProperties() {
        setCapacity(60);
        setInitialTokens(60);
        setTokensPerPeriod(1);
        setRefillIntervalMillis(1_000);
    }
}
