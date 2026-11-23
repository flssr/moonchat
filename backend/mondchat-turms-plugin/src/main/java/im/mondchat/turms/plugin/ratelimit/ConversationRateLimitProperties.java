package im.mondchat.turms.plugin.ratelimit;

import org.springframework.boot.context.properties.ConfigurationProperties;
import im.turms.server.common.infra.property.env.common.BaseRateLimitingProperties;

/** 会话级桶：`turms-plugin.mondchat-ratelimit.conversation.*`，默认 20/分钟。 */
@ConfigurationProperties("turms-plugin.mondchat-ratelimit.conversation")
public class ConversationRateLimitProperties extends BaseRateLimitingProperties {
}
