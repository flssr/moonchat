package im.mondchat.biz.config;

import java.nio.file.Path;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/** `mondchat.turms.*`：im-facade 打 Turms 需要的地址、凭据与共享 HMAC 密钥。 */
@ConfigurationProperties("mondchat.turms")
public record TurmsProperties(
        String adminUrl,
        String adminUsername,
        String adminPassword,
        String gatewayUrl,
        Path jwtSecretFile,
        Duration credentialTtl,
        /** 群投影重放器的扫描间隔（30 秒，未确认）：失败的群最多晚这么久收敛。 */
        Duration replayInterval,
        /**
         * 客户端直写开关（切换前默认关闭）：关闭时只签 `QUERY`，与切换前的行为逐字节一致；
         * 打开后正常账号多授 `MESSAGE.CREATE/UPDATE` 与 `CONVERSATION.UPDATE`，冻结账号只 `QUERY` +
         * `CONVERSATION.UPDATE`（能清角标、发不出消息）。与 `allowSendMessagesToStranger=false`
         * 必须同一次切换（docs/truth/backend/identity.md）。
         */
        boolean writeCredentialEnabled) {
}
