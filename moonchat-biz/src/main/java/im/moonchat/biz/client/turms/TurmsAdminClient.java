package im.moonchat.biz.client.turms;

import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.config.TurmsProperties;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/** im-facade 的建用户那一支手：Turms Admin REST，Basic 认证。 */
@Slf4j
@Component
public class TurmsAdminClient {

    private static final SecureRandom RANDOM = new SecureRandom();

    private final RestClient restClient;

    public TurmsAdminClient(TurmsProperties properties) {
        this.restClient = RestClient.builder()
                .baseUrl(properties.adminUrl())
                .defaultHeaders(headers -> headers.setBasicAuth(properties.adminUsername(), properties.adminPassword()))
                .build();
    }

    /**
     * 用 Biz 生成的账号 id 建 Turms 用户（Admin API 接受指定 id，冒烟已实测）。
     * Turms 要求密码非空且 ≤ 16 字符，但平台不保存也不分发它——客户端只用 JWT 登录。
     */
    public void createUser(long accountId, String displayName) {
        try {
            restClient.post()
                    .uri("/users")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of(
                            "id", accountId,
                            "name", displayName,
                            "isActive", true,
                            "password", throwawayPassword()))
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            // 没拿到 Turms 的确认就不再往下走：调用方连同 PG 行一起回滚，不留孤儿账号。
            // 原因只进结构化日志（V1 不建审计表），否则失败现场只剩一个 503。
            log.warn("建 Turms 用户失败：accountId={}", accountId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /**
     * 改名同步：Admin `PUT /users?ids=`（`UpdateUserDTO` 只带 name，别的字段留空即不改）。
     * 没拿到确认就抛 503，调用方的事务连同名字一起回滚（docs/api-contracts.md §4.3）。
     */
    public void updateUserName(long accountId, String displayName) {
        try {
            restClient.put()
                    .uri(uri -> uri.path("/users").queryParam("ids", accountId).build())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("name", displayName))
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            log.warn("同步名字进 Turms 失败：accountId={}", accountId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    private static String throwawayPassword() {
        byte[] bytes = new byte[9];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
