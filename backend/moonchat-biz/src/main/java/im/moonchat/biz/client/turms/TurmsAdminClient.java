package im.moonchat.biz.client.turms;

import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.config.TurmsProperties;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import tools.jackson.databind.JsonNode;

/**
 * im-facade 打 Turms Admin REST 的那几支手：建用户、改名、建群与成员集合。
 * 业务代码一律经这里，不自己拼 Admin 调用。
 */
@Slf4j
@Component
public class TurmsAdminClient {

    /** Turms 默认 GroupType 0：邀请制、成员可见、guest 不可发言（docs/truth/architecture.md）。 */
    private static final int MEMBER_ONLY_GROUP_TYPE = 0;

    /** Admin 单次查询最多回 1000 条（`maxAvailableRecordsPerRequest`），成员集合按页取。 */
    private static final int MEMBER_PAGE_SIZE = 1000;

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
     * 没拿到确认就抛 503，调用方的事务连同名字一起回滚（docs/truth/backend/identity.md）。
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

    /**
     * 建群：`AddGroupDTO` 不能指定 id，所以 group id 由 Turms 生成并返回，Biz 回填
     * `room_info.turms_group_id`（docs/truth/backend/room.md）。
     */
    public long createGroup(long ownerAccountId, String name) {
        try {
            JsonNode body = restClient.post()
                    .uri("/groups")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of(
                            "typeId", MEMBER_ONLY_GROUP_TYPE,
                            "creatorId", ownerAccountId,
                            "ownerId", ownerAccountId,
                            "name", name))
                    .retrieve()
                    .body(JsonNode.class);
            return body.path("data").path("id").asLong();
        } catch (RestClientException e) {
            log.warn("建 Turms group 失败：ownerAccountId={}", ownerAccountId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** Turms 侧这个群还在不在：丢了就按 PG 重建（投影只有一个方向，PG 为准）。查不到时 Admin 回 204。 */
    public boolean groupExists(long turmsGroupId) {
        try {
            JsonNode body = restClient.get()
                    .uri(uri -> uri.path("/groups").queryParam("ids", turmsGroupId).build())
                    .retrieve()
                    .body(JsonNode.class);
            return body != null && !body.path("data").isEmpty();
        } catch (RestClientException e) {
            log.warn("查 Turms group 失败：turmsGroupId={}", turmsGroupId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** Turms 侧当前的成员集合：投影拿它和 PG 的有效行做差集，所以这里是投影的唯一读回。 */
    public Set<Long> groupMemberIds(long turmsGroupId) {
        Set<Long> accountIds = new LinkedHashSet<>();
        try {
            for (int page = 0; ; page++) {
                int current = page;
                JsonNode body = restClient.get()
                        .uri(uri -> uri.path("/groups/members/page")
                                .queryParam("groupIds", turmsGroupId)
                                .queryParam("page", current)
                                .queryParam("size", MEMBER_PAGE_SIZE)
                                .build())
                        .retrieve()
                        .body(JsonNode.class);
                if (body == null) {
                    return accountIds;
                }
                JsonNode records = body.path("data").path("records");
                records.forEach(record -> accountIds.add(record.path("key").path("userId").asLong()));
                if (records.size() < MEMBER_PAGE_SIZE) {
                    return accountIds;
                }
            }
        } catch (RestClientException e) {
            log.warn("读 Turms 群成员失败：turmsGroupId={}", turmsGroupId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** 把一个人加进 Turms 的群（Admin 一次一个成员）。 */
    public void addGroupMember(long turmsGroupId, long accountId) {
        try {
            restClient.post()
                    .uri("/groups/members")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("groupId", turmsGroupId, "userId", accountId, "role", "MEMBER"))
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            log.warn("往 Turms 群里加成员失败：turmsGroupId={} accountId={}", turmsGroupId, accountId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** 把一个人从 Turms 的群里移出（`keys[0].*` 是 Admin 的复合主键入参形状，冒烟已实测）。 */
    public void removeGroupMember(long turmsGroupId, long accountId) {
        try {
            restClient.delete()
                    .uri(uri -> uri.path("/groups/members")
                            .queryParam("keys[0].groupId", turmsGroupId)
                            .queryParam("keys[0].userId", accountId)
                            .build())
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            log.warn("从 Turms 群里移除成员失败：turmsGroupId={} accountId={}", turmsGroupId, accountId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /**
     * 代发消息：Admin `POST /messages`，带已认证的 `senderId`、设备类型与来源 IP。
     * 消息 id 由写入网关生成后在这里一并提交（Admin 不回传 id），`isSystemMessage` 恒为 false。
     * 返回后 Turms 仍会用自己的投影再校验一次（群成员、黑名单）。
     */
    public void sendMessage(long messageId, long senderId, String senderDeviceType, boolean groupMessage,
            long targetId, String text, String senderIp) {
        Map<String, Object> body = new HashMap<>();
        body.put("id", messageId);
        body.put("senderId", senderId);
        body.put("senderDeviceType", senderDeviceType);
        body.put("isGroupMessage", groupMessage);
        body.put("isSystemMessage", false);
        body.put("targetId", targetId);
        body.put("text", text);
        if (senderIp != null) {
            body.put("senderIp", senderIp);
        }
        try {
            restClient.post()
                    .uri("/messages")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            // 没拿到确认就回 503：Turms 可能已经落库，重试可能重复（不做幂等，已写的行为）
            log.warn("代发消息失败：messageId={} senderId={} targetId={}", messageId, senderId, targetId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    private static String throwawayPassword() {
        byte[] bytes = new byte[9];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
