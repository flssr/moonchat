package im.moonchat.biz;

import com.redis.testcontainers.RedisContainer;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * 测试期的外部世界：真 PG、真 Redis、一个只监听 127.0.0.1 的假 Turms Admin 端点。
 * 单例是为了让所有测试类共用一套容器（Spring 上下文因此能缓存）。
 * Turms 本身不在容器里起——它是否真的认这份凭据，由 infra/turms/smoke 的脚本断言。
 */
final class TestStack {

    static final String LOGIN_JWT_SECRET = "test-login-jwt-secret-0123456789abcdef";
    static final String AGENT_KEY_PEPPER = "test-agent-key-pepper-0123456789abcdef";

    static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer(DockerImageName.parse("postgres:17-alpine"));
    static final RedisContainer REDIS = new RedisContainer(DockerImageName.parse("redis:8.0.3-alpine"));
    static final FakeTurmsAdmin TURMS_ADMIN = FakeTurmsAdmin.start();
    static final Path JWT_SECRET_FILE = writeSecret();

    static {
        POSTGRES.start();
        REDIS.start();
    }

    private TestStack() {
    }

    static void register(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.data.redis.host", REDIS::getRedisHost);
        registry.add("spring.data.redis.port", REDIS::getRedisPort);
        registry.add("moonchat.turms.admin-url", TURMS_ADMIN::baseUrl);
        registry.add("moonchat.turms.jwt-secret-file", () -> JWT_SECRET_FILE.toString());
        registry.add("moonchat.auth.jwt-secret", () -> LOGIN_JWT_SECRET);
        registry.add("moonchat.agent.key-pepper", () -> AGENT_KEY_PEPPER);
    }

    /** 与 turms-gateway 共享的那份密钥：32 字节，HS256 的最小长度。 */
    private static Path writeSecret() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        try {
            Path file = Files.createTempFile("moonchat-jwt-hmac256", ".key");
            Files.write(file, bytes);
            file.toFile().deleteOnExit();
            return file;
        } catch (IOException e) {
            throw new UncheckedIOException("写不出测试用的 HMAC 密钥文件", e);
        }
    }
}
