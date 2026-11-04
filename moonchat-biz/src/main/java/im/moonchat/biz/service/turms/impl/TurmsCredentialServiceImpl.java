package im.moonchat.biz.service.turms.impl;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import im.moonchat.biz.config.TurmsProperties;
import im.moonchat.biz.service.turms.TurmsCredentialService;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class TurmsCredentialServiceImpl implements TurmsCredentialService {

    /** 只授查询：客户端能登录、收推送、查历史，但发不出消息、也建不了 group。 */
    private static final List<Map<String, Object>> QUERY_ONLY = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")));

    private final MACSigner signer;
    private final Duration ttl;

    public TurmsCredentialServiceImpl(TurmsProperties properties) {
        try {
            this.signer = new MACSigner(Files.readAllBytes(properties.jwtSecretFile()));
        } catch (IOException e) {
            throw new UncheckedIOException("读不到与 Turms 共享的 HMAC 密钥文件：" + properties.jwtSecretFile(), e);
        } catch (JOSEException e) {
            throw new IllegalStateException("HMAC 密钥不足 256 位，Turms 会拒绝验签：" + properties.jwtSecretFile(), e);
        }
        this.ttl = properties.credentialTtl();
    }

    @Override
    public Credential sign(long accountId) {
        Instant expiresAt = Instant.now().plus(ttl).truncatedTo(ChronoUnit.SECONDS);
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .subject(Long.toString(accountId))
                .expirationTime(Date.from(expiresAt))
                // gateway 默认期望这个 claim，缺了会以 2011 拒绝登录（冒烟实测）。
                .claim("authenticated", true)
                .claim("statements", QUERY_ONLY)
                .build();
        SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
        try {
            jwt.sign(signer);
        } catch (JOSEException e) {
            throw new IllegalStateException("签 Turms 凭据失败", e);
        }
        return new Credential(jwt.serialize(), expiresAt);
    }
}
