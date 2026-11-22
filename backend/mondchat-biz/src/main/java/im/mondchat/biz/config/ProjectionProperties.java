package im.mondchat.biz.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * `mondchat.projection.*`：投影派发与对账的开关与节奏（docs/truth/backend/projection.md）。
 * `enabled=false` 时派发与对账都不跑，事件只累积——灰度回退用这个开关，不删数据。
 */
@ConfigurationProperties("mondchat.projection")
public record ProjectionProperties(boolean enabled, long dispatchIntervalMs, int batchSize,
        String reconcileCron) {
}
