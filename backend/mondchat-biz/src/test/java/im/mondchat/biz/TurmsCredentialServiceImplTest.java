package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.config.TurmsAdminHttpProperties;
import im.mondchat.biz.config.TurmsProperties;
import im.mondchat.biz.service.turms.TurmsCredentialService;
import im.mondchat.biz.service.turms.impl.TurmsCredentialServiceImpl;
import java.nio.file.Files;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** 签发侧的两套 statements 与冻结踢会话（不需要 Spring 上下文，直接构造实现类）。 */
class TurmsCredentialServiceImplTest {

    private static final long ACCOUNT_ID = 100_000_001L;

    private static final List<Map<String, Object>> QUERY_ONLY = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")));

    private static final List<Map<String, Object>> WRITE_AND_READ = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")),
            Map.of("effect", "ALLOW", "actions", List.of("CREATE", "UPDATE"), "resources", List.of("MESSAGE")),
            Map.of("effect", "ALLOW", "actions", List.of("UPDATE"), "resources", List.of("CONVERSATION")));

    private static final List<Map<String, Object>> READ_AND_READ_MARKER = List.of(
            Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*")),
            Map.of("effect", "ALLOW", "actions", List.of("UPDATE"), "resources", List.of("CONVERSATION")));

    private static TurmsProperties properties(boolean writeCredentialEnabled) {
        return new TurmsProperties("http://localhost:8510", "turms", "turms", "ws://localhost:20510",
                TestStack.JWT_SECRET_FILE, Duration.ofHours(12), Duration.ofSeconds(30), writeCredentialEnabled,
                new TurmsAdminHttpProperties(null, null));
    }

    private static JWTClaimsSet claims(TurmsCredentialService.Credential credential) throws Exception {
        SignedJWT jwt = SignedJWT.parse(credential.token());
        assertThat(jwt.verify(new MACVerifier(Files.readAllBytes(TestStack.JWT_SECRET_FILE)))).isTrue();
        return jwt.getJWTClaimsSet();
    }

    @Test
    void 开关关闭时正常账号与冻结账号都只签查询() throws Exception {
        TurmsAdminClient admin = mock(TurmsAdminClient.class);
        TurmsCredentialServiceImpl service = new TurmsCredentialServiceImpl(properties(false), admin);

        assertThat(claims(service.sign(ACCOUNT_ID, false)).getClaim("statements")).isEqualTo(QUERY_ONLY);
        assertThat(claims(service.sign(ACCOUNT_ID, true)).getClaim("statements")).isEqualTo(QUERY_ONLY);
        // 关闭时不踢人：行为与切换前一致
        verifyNoInteractions(admin);
    }

    @Test
    void 开关打开时正常账号多授发消息撤回与清角标() throws Exception {
        TurmsAdminClient admin = mock(TurmsAdminClient.class);
        TurmsCredentialServiceImpl service = new TurmsCredentialServiceImpl(properties(true), admin);

        JWTClaimsSet claims = claims(service.sign(ACCOUNT_ID, false));

        assertThat(claims.getClaim("statements")).isEqualTo(WRITE_AND_READ);
        assertThat(claims.getSubject()).isEqualTo(Long.toString(ACCOUNT_ID));
        assertThat(claims.getBooleanClaim("authenticated")).isTrue();
        verify(admin, never()).disconnectSessions(ACCOUNT_ID);
    }

    @Test
    void 开关打开时冻结账号只留查询与清角标并踢掉存量会话() throws Exception {
        TurmsAdminClient admin = mock(TurmsAdminClient.class);
        TurmsCredentialServiceImpl service = new TurmsCredentialServiceImpl(properties(true), admin);

        assertThat(claims(service.sign(ACCOUNT_ID, true)).getClaim("statements"))
                .isEqualTo(READ_AND_READ_MARKER);
        // 不踢的话，冻结前签出的那份仍带写权限（最长 12 小时）
        verify(admin).disconnectSessions(ACCOUNT_ID);
    }

    @Test
    void 踢会话失败不影响签发() throws Exception {
        TurmsAdminClient admin = mock(TurmsAdminClient.class);
        org.mockito.Mockito.doThrow(new IllegalStateException("admin 挂了"))
                .when(admin)
                .disconnectSessions(ACCOUNT_ID);
        TurmsCredentialServiceImpl service = new TurmsCredentialServiceImpl(properties(true), admin);

        // admin 抛异常也要能签出：客户端拿到只读凭据，只是旧会话要等它自己过期
        assertThat(claims(service.sign(ACCOUNT_ID, true)).getClaim("statements"))
                .isEqualTo(READ_AND_READ_MARKER);
    }
}
