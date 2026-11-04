package im.moonchat.biz.auth;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import im.moonchat.biz.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.text.ParseException;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import org.springframework.stereotype.Component;

/**
 * 登录 JWT：只对 Biz 有效（认作 `owner` 来源），与 Turms 凭据是两份东西。
 * 无状态——不写 PG、不存凭据记录；续期就是从「现在」重算 7 天（docs/api-contracts.md §3.4）。
 */
@Component
public class LoginTokenService {

    private final MACSigner signer;
    private final MACVerifier verifier;
    private final Duration ttl;

    LoginTokenService(AuthProperties properties) {
        byte[] secret = properties.jwtSecret().getBytes(StandardCharsets.UTF_8);
        try {
            this.signer = new MACSigner(secret);
            this.verifier = new MACVerifier(secret);
        } catch (JOSEException e) {
            throw new IllegalStateException("登录 JWT 密钥不足 256 位", e);
        }
        this.ttl = properties.loginTokenTtl();
    }

    public Issued issue(long accountId) {
        Instant expiresAt = Instant.now().plus(ttl).truncatedTo(ChronoUnit.SECONDS);
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .subject(Long.toString(accountId))
                .expirationTime(Date.from(expiresAt))
                .build();
        SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
        try {
            jwt.sign(signer);
        } catch (JOSEException e) {
            throw new IllegalStateException("签登录 JWT 失败", e);
        }
        return new Issued(jwt.serialize(), expiresAt);
    }

    /** 验签 + 未过期，取出 account_id；任何一处不合格都只回 unauthenticated。 */
    public long verify(String token) {
        try {
            SignedJWT jwt = SignedJWT.parse(token);
            Date expiration = jwt.getJWTClaimsSet().getExpirationTime();
            boolean fresh = expiration != null && expiration.toInstant().isAfter(Instant.now());
            boolean expectedAlgorithm = JWSAlgorithm.HS256.equals(jwt.getHeader().getAlgorithm());
            if (!expectedAlgorithm || !fresh || !jwt.verify(verifier)) {
                throw ApiException.unauthenticated();
            }
            return Long.parseLong(jwt.getJWTClaimsSet().getSubject());
        } catch (ParseException | JOSEException | NumberFormatException e) {
            throw ApiException.unauthenticated();
        }
    }

    public record Issued(String token, Instant expiresAt) {
    }
}
