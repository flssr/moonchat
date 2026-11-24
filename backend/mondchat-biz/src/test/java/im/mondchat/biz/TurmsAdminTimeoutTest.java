package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.TurmsAdminHttpProperties;
import im.mondchat.biz.config.TurmsProperties;
import java.net.ServerSocket;
import java.net.Socket;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;

/** Turms 卡死时 Admin 调用必须有界：读超时与连接失败都落回既有的 503。 */
class TurmsAdminTimeoutTest {

    @Test
    void 默认连接与读取超时是两秒和五秒() {
        TurmsAdminHttpProperties properties = new TurmsAdminHttpProperties(null, null);

        assertThat(properties.connectTimeout()).isEqualTo(Duration.ofSeconds(2));
        assertThat(properties.readTimeout()).isEqualTo(Duration.ofSeconds(5));
    }

    @Test
    void 服务端收下不回包时按读超时回上游不可用() throws Exception {
        try (ServerSocket server = new ServerSocket(0)) {
            CompletableFuture<Void> accepted = CompletableFuture.runAsync(() -> {
                try (Socket ignored = server.accept()) {
                    Thread.sleep(1500);
                } catch (Exception ignored) {
                    // 客户端超时后会先断；这里只负责让连接挂着。
                }
            });

            TurmsAdminClient client = client("http://127.0.0.1:" + server.getLocalPort(), 200, 200);
            long start = System.nanoTime();

            assertThatThrownBy(() -> client.userExists(1))
                    .isInstanceOfSatisfying(ApiException.class,
                            error -> assertThat(error.getCode()).isEqualTo("upstream_unavailable"));

            assertThat(Duration.ofNanos(System.nanoTime() - start)).isLessThan(Duration.ofSeconds(2));
            accepted.get(3, TimeUnit.SECONDS);
        }
    }

    @Test
    void 端口关闭时连接快速失败并回上游不可用() throws Exception {
        int port;
        try (ServerSocket probe = new ServerSocket(0)) {
            port = probe.getLocalPort();
        }

        TurmsAdminClient client = client("http://127.0.0.1:" + port, 300, 300);
        long start = System.nanoTime();

        assertThatThrownBy(() -> client.userExists(1))
                .isInstanceOfSatisfying(ApiException.class,
                        error -> assertThat(error.getCode()).isEqualTo("upstream_unavailable"));

        assertThat(Duration.ofNanos(System.nanoTime() - start)).isLessThan(Duration.ofSeconds(2));
    }

    private static TurmsAdminClient client(String adminUrl, long connectMillis, long readMillis) {
        return new TurmsAdminClient(new TurmsProperties(
                adminUrl,
                "turms",
                "turms",
                "ws://localhost:20510",
                null,
                Duration.ofHours(1),
                Duration.ofSeconds(30),
                false,
                new TurmsAdminHttpProperties(
                        Duration.ofMillis(connectMillis),
                        Duration.ofMillis(readMillis))));
    }
}
