package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/** 接口测试的公共件：真容器 + 假 Turms Admin + 几处容易重复的调用。 */
@SpringBootTest
@AutoConfigureMockMvc
abstract class ApiTestSupport {

    private static final AtomicInteger SEQUENCE = new AtomicInteger();

    @Autowired
    MockMvc mockMvc;

    @Autowired
    JdbcTemplate jdbc;

    @DynamicPropertySource
    static void stackProperties(DynamicPropertyRegistry registry) {
        TestStack.register(registry);
    }

    @BeforeEach
    void resetTurmsAdmin() {
        TestStack.TURMS_ADMIN.reset();
    }

    static String uniqueEmail() {
        return "user" + SEQUENCE.incrementAndGet() + "@example.com";
    }

    static String bearer(String token) {
        return "Bearer " + token;
    }

    String register(String email, String password, String displayName) throws Exception {
        return mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"%s","display_name":"%s"}
                                """.formatted(email, password, displayName)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    /** 注册并登录一个全新账号；大多数测试只关心「有个已认证的调用方」。 */
    Caller newCaller() throws Exception {
        String email = uniqueEmail();
        long accountId = ((Number) JsonPath.read(register(email, "secret123", "路人"), "$.account_id")).longValue();
        return new Caller(accountId, login(email, "secret123"));
    }

    record Caller(long accountId, String token) {
    }

    /** 归属者建一个 agent：`accountKey` 就是 #3 密钥形态的凭据。 */
    Agent newAgent(Caller owner, String displayName) throws Exception {
        String body = mockMvc.perform(post("/api/agent-accounts")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"%s"}
                                """.formatted(displayName)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return new Agent(((Number) JsonPath.read(body, "$.account_id")).longValue(),
                JsonPath.read(body, "$.account_key"));
    }

    record Agent(long accountId, String accountKey) {
    }

    String loginBody(String email, String password) throws Exception {
        return mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"%s"}
                                """.formatted(email, password)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    String login(String email, String password) throws Exception {
        return tokenOf(loginBody(email, password));
    }

    long accountIdOf(String loginBody) {
        return ((Number) JsonPath.read(loginBody, "$.account.account_id")).longValue();
    }

    String tokenOf(String loginBody) {
        return JsonPath.read(loginBody, "$.token");
    }

    /** 登录 JWT 得用 Biz 自己的密钥才验得开（Turms 的密钥是另一把）。 */
    JWTClaimsSet loginClaims(String token) throws Exception {
        SignedJWT jwt = SignedJWT.parse(token);
        assertThat(jwt.verify(new MACVerifier(TestStack.LOGIN_JWT_SECRET.getBytes(StandardCharsets.UTF_8))))
                .isTrue();
        return jwt.getJWTClaimsSet();
    }

    /**
     * 两枪并发打同一个 POST：撞的是「先查后写」的窗口（约 1ms），不命中也是正常结果，
     * 所以调用方的断言只能是「状态码不落在 5xx」。
     */
    List<Integer> racePost(String path, String token, String body) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Future<Integer>> shots = new ArrayList<>();
            for (int i = 0; i < 2; i++) {
                shots.add(pool.submit(() -> {
                    start.await();
                    return mockMvc.perform(post(path)
                                    .header(HttpHeaders.AUTHORIZATION, bearer(token))
                                    .contentType(MediaType.APPLICATION_JSON)
                                    .content(body))
                            .andReturn().getResponse().getStatus();
                }));
            }
            start.countDown();
            List<Integer> codes = new ArrayList<>();
            for (Future<Integer> shot : shots) {
                codes.add(shot.get());
            }
            return codes;
        } finally {
            pool.shutdownNow();
        }
    }

    /** 建 agent 账号的接口在 S2，所以 S1 的测试直接落一行 agent（归属、资料齐全）。 */
    long insertAgent(long ownerAccountId, String displayName, Instant createdAt) {
        Long accountId = jdbc.queryForObject("""
                insert into account (type, owner_account_id, turms_sync_state, created_at)
                values ('agent', ?, 'synced', ?)
                returning id
                """, Long.class, ownerAccountId, Timestamp.from(createdAt));
        jdbc.update("""
                insert into account_info (account_id, display_name, credential_hash)
                values (?, ?, ?)
                """, accountId, displayName, "hmac-sha256$" + accountId);
        return accountId;
    }
}
