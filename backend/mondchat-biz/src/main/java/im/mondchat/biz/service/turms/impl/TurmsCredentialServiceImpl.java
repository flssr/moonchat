package im.mondchat.biz.service.turms.impl;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.config.TurmsProperties;
import im.mondchat.biz.service.turms.TurmsCredentialService;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class TurmsCredentialServiceImpl implements TurmsCredentialService {

    /** 切换前唯一的一套：只授查询（能登录、收推送、查历史，但发不出消息、也建不了 group）。 */
    private static final List<Map<String, Object>> QUERY_ONLY = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")));

    /** 直写打开后（正常账号）：查询 + 发消息/撤回 + 清角标。 */
    private static final List<Map<String, Object>> WRITE_AND_READ = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")),
            Map.of("effect", "ALLOW", "actions", List.of("CREATE", "UPDATE"), "resources", List.of("MESSAGE")),
            Map.of("effect", "ALLOW", "actions", List.of("UPDATE"), "resources", List.of("CONVERSATION")));

    /** 直写打开后（冻结账号）：能读、能清角标，发不出消息。 */
    private static final List<Map<String, Object>> READ_AND_READ_MARKER = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")),
            Map.of("effect", "ALLOW", "actions", List.of("UPDATE"), "resources", List.of("CONVERSATION")));

    private final MACSigner signer;
    private final Duration ttl;
    private final boolean writeCredentialEnabled;
    private final TurmsAdminClient turmsAdmin;

    public TurmsCredentialServiceImpl(TurmsProperties properties, TurmsAdminClient turmsAdmin) {
        try {
            this.signer = new MACSigner(Files.readAllBytes(properties.jwtSecretFile()));
        } catch (IOException e) {
            throw new UncheckedIOException("读不到与 Turms 共享的 HMAC 密钥文件：" + properties.jwtSecretFile(), e);
        } catch (JOSEException e) {
            throw new IllegalStateException("HMAC 密钥不足 256 位，Turms 会拒绝验签：" + properties.jwtSecretFile(), e);
        }
        this.ttl = properties.credentialTtl();
        this.writeCredentialEnabled = properties.writeCredentialEnabled();
        this.turmsAdmin = turmsAdmin;
    }

    @Override
    public Credential sign(long accountId, boolean frozen) {
        Instant expiresAt = Instant.now().plus(ttl).truncatedTo(ChronoUnit.SECONDS);
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .subject(Long.toString(accountId))
                .expirationTime(Date.from(expiresAt))
                // gateway 默认期待这个 claim，缺了会以 2011 拒绝登录（冒烟实测）。
                .claim("authenticated", true)
                .claim("statements", statementsFor(frozen))
                .build();
        SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
        try {
            jwt.sign(signer);
        } catch (JOSEException e) {
            throw new IllegalStateException("签 Turms 凭据失败", e);
        }
        // 冻结账号：签只读凭据的同时踢掉存量会话，否则冻结前签出的那份仍带写权限（最长 12 小时）。
        if (writeCredentialEnabled && frozen) {
            kickSessions(accountId);
        }
        return new Credential(jwt.serialize(), expiresAt);
    }

    /** 开关关闭时无论账号状态都只签 `QUERY`：与切换前的签发逐字节一致。 */
    private List<Map<String, Object>> statementsFor(boolean frozen) {
        if (!writeCredentialEnabled) {
            return QUERY_ONLY;
        }
        return frozen ? READ_AND_READ_MARKER : WRITE_AND_READ;
    }

    private void kickSessions(long accountId) {
        try {
            turmsAdmin.disconnectSessions(accountId);
        } catch (RuntimeException e) {
            // 踢失败不回滚签发：客户端拿到的仍是只读凭据，只是旧会话要等它自己过期
            log.warn("冻结账号的存量会话没踢掉：accountId={}", accountId, e);
        }
    }
}
