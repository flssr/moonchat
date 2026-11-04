package im.moonchat.biz;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

/**
 * 假的 Turms Admin：只实现 im-facade 会打的那一条 `POST /users`。
 * 它让接口测试不必拖起整套 Turms 编排，同时仍走真实的 RestClient（Basic 认证与 JSON 形状都被验到）。
 */
final class FakeTurmsAdmin {

    private final HttpServer server;
    private volatile int status = 200;
    private volatile String lastPath;
    private volatile String lastBody;
    private volatile String lastAuthorization;

    private FakeTurmsAdmin(HttpServer server) {
        this.server = server;
    }

    static FakeTurmsAdmin start() {
        try {
            HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            FakeTurmsAdmin admin = new FakeTurmsAdmin(server);
            server.createContext("/", admin::handle);
            server.start();
            return admin;
        } catch (IOException e) {
            throw new UncheckedIOException("假 Turms Admin 起不来", e);
        }
    }

    String baseUrl() {
        return "http://127.0.0.1:" + server.getAddress().getPort();
    }

    FakeTurmsAdmin reset() {
        status = 200;
        lastPath = null;
        lastBody = null;
        lastAuthorization = null;
        return this;
    }

    /** 让下一次调用失败，用来验「建用户失败要连同账号行回滚」。 */
    FakeTurmsAdmin respondWith(int statusCode) {
        this.status = statusCode;
        return this;
    }

    String lastPath() {
        return lastPath;
    }

    String lastBody() {
        return lastBody;
    }

    String lastAuthorization() {
        return lastAuthorization;
    }

    private void handle(com.sun.net.httpserver.HttpExchange exchange) throws IOException {
        lastPath = exchange.getRequestURI().getPath();
        lastAuthorization = exchange.getRequestHeaders().getFirst("Authorization");
        lastBody = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(status, -1);
        exchange.close();
    }
}
