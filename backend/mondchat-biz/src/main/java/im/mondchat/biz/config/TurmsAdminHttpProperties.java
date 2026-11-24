package im.mondchat.biz.config;

import java.time.Duration;

/**
 * `mondchat.turms.http.*`：Biz 调 Turms Admin 的 HTTP 超时。
 *
 * <p>Turms 只卡不回时不能无限占线程；超时抛的 {@code ResourceAccessException} 是
 * {@code RestClientException} 子类，会落进 {@code TurmsAdminClient} 既有 catch，外部仍是
 * {@code 503 upstream_unavailable}。派发器再按既有退避重试，积压可见且能自愈。
 */
public record TurmsAdminHttpProperties(Duration connectTimeout, Duration readTimeout) {

    public static final Duration DEFAULT_CONNECT_TIMEOUT = Duration.ofSeconds(2);
    public static final Duration DEFAULT_READ_TIMEOUT = Duration.ofSeconds(5);

    public TurmsAdminHttpProperties {
        connectTimeout = connectTimeout == null ? DEFAULT_CONNECT_TIMEOUT : connectTimeout;
        readTimeout = readTimeout == null ? DEFAULT_READ_TIMEOUT : readTimeout;
    }
}
