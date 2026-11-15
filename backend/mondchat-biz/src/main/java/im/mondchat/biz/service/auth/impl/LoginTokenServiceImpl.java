package im.mondchat.biz.service.auth.impl;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.AuthProperties;
import im.mondchat.biz.service.auth.LoginTokenService;
import java.nio.charset.StandardCharsets;
import java.text.ParseException;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import org.springframework.stereotype.Service;

@Service
public class LoginTokenServiceImpl implements LoginTokenService {

    private final MACSigner signer;
    private final MACVerifier verifier;
    private final Duration ttl;

    public LoginTokenServiceImpl(AuthProperties properties) {
        byte[] secret = properties.jwtSecret().getBytes(StandardCharsets.UTF_8);
        try {
            this.signer = new MACSigner(secret);
            this.verifier = new MACVerifier(secret);
        } catch (JOSEException e) {
            throw new IllegalStateException("登录 JWT 密钥不足 256 位", e);
        }
        this.ttl = properties.loginTokenTtl();
    }

    @Override
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

    @Override
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
}
