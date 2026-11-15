package im.mondchat.biz.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/** `mondchat.auth.*`：登录 JWT 自签自验用的密钥与时长（与 Turms 的 HMAC 密钥相互独立）。 */
@ConfigurationProperties("mondchat.auth")
public record AuthProperties(String jwtSecret, Duration loginTokenTtl) {
}
