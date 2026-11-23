package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.TurmsAdminHttpProperties;
import im.mondchat.biz.config.TurmsProperties;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

/**
 * Turms 只卡不回（不是连不上）时，Admin 调用必须在读超时后失败，而不是一直占着调用线程。
 * 用真实 socket 打，不 mock RestClient：要验的正是「底层超时真的接上了」。
 */
class TurmsAdminClientTimeoutTest {

    private static TurmsAdminClient client(String adminUrl, Duration connect, Duration read) {
        return new TurmsAdminClient(
                new TurmsProperties(adminUrl, "turms", "turms", "ws://localhost:20510",
                        TestStack.JWT_SECRET_FILE, Duration.ofHours(12), Duration.ofSeconds(30), false),
                new TurmsAdminHttpProperties(connect, read));
    }

    @Test
    void 服务端不回包时读超时后失败且不挂住() throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        // 收下请求但 30 秒不回：模拟「TCP 通、Turms 卡住」这种最难判的故障。
        server.createContext("/users", exchange -> {
            try {
                Thread.sleep(30_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            exchange.close();
        });
        server.start();
        try {
            TurmsAdminClient client = client("http://127.0.0.1:" + server.getAddress().getPort(),
                    Duration.ofSeconds(2), Duration.ofMillis(300));
            long start = System.nanoTime();
            assertThatThrownBy(() -> client.userExists(42L))
                    .isInstanceOf(ApiException.class)
                    .satisfies(e -> {
                        assertThat(((ApiException) e).getCode()).isEqualTo("upstream_unavailable");
                        assertThat(((ApiException) e).getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
                    });
            long elapsedMillis = Duration.ofNanos(System.nanoTime() - start).toMillis();
            assertThat(elapsedMillis).isLessThan(5_000L);
        } finally {
            server.stop(0);
        }
    }

    @Test
    void 连不上时按连接超时快速失败() throws IOException {
        // 拿一个端口然后立刻关掉：连上去必定被拒，不会真的等满 connectTimeout。
        int port;
        try (ServerSocket socket = new ServerSocket(0)) {
            port = socket.getLocalPort();
        }
        TurmsAdminClient client = client("http://127.0.0.1:" + port, Duration.ofMillis(500), Duration.ofSeconds(5));
        assertThatThrownBy(() -> client.userExists(42L))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).getCode()).isEqualTo("upstream_unavailable"));
    }
}
