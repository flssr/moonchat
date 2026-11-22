package im.mondchat.turms.plugin.ratelimit;

import org.springframework.boot.context.properties.ConfigurationProperties;
import im.turms.server.common.infra.property.env.common.BaseRateLimitingProperties;

/**
 * 账号级桶：`turms-plugin.mondchat-ratelimit.account.*`。
 * 默认 60/分钟（容量 60、每分钟补 60 个），与今天 Biz 的 `mondchat.limit.account-per-minute` 同义。
 */
@ConfigurationProperties("turms-plugin.mondchat-ratelimit.account")
public class AccountRateLimitProperties extends BaseRateLimitingProperties {
}
