package im.moonchat.biz.config;

import java.nio.file.Path;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/** `moonchat.turms.*`：im-facade 打 Turms 需要的地址、凭据与共享 HMAC 密钥。 */
@ConfigurationProperties("moonchat.turms")
public record TurmsProperties(
        String adminUrl,
        String adminUsername,
        String adminPassword,
        String gatewayUrl,
        Path jwtSecretFile,
        Duration credentialTtl,
        /** 群投影重放器的扫描间隔（30 秒，未确认）：失败的群最多晚这么久收敛。 */
        Duration replayInterval) {
}
