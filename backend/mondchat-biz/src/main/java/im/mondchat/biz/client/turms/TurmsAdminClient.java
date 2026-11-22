package im.mondchat.biz.client.turms;

import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.TurmsProperties;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
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
     * 关系投影的读回：`GET /users/relationships?ownerIds=&relatedUserIds=` 找一条 `(owner, related)` 行。
     * 返回 null 表示 Turms 还没有这一行；派发器据此决定 POST 还是 PUT（避免「PUT 未命中静默成功」）。
     */
    public Relationship queryRelationship(long ownerId, long relatedUserId) {
        try {
            JsonNode body = restClient.get()
                    .uri(uri -> uri.path("/users/relationships")
                            .queryParam("ownerIds", ownerId)
                            .queryParam("relatedUserIds", relatedUserId)
                            .queryParam("size", 1)
                            .build())
                    .retrieve()
                    .body(JsonNode.class);
            JsonNode data = body == null ? null : body.path("data");
            if (data == null || !data.isArray() || data.isEmpty()) {
                return null;
            }
            JsonNode row = data.get(0);
            return new Relationship(row.path("key").path("ownerId").asLong(),
                    row.path("key").path("relatedUserId").asLong(),
                    dateOrNull(row.path("blockDate")),
                    dateOrNull(row.path("establishmentDate")));
        } catch (RestClientException e) {
            log.warn("读 Turms 关系失败：ownerId={} relatedUserId={}", ownerId, relatedUserId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** 关系投影：建一行。`establishmentDate` 用 epoch-0 表示「只拉黑、不是好友」。 */
    public void createRelationship(long ownerId, long relatedUserId, Long blockDate, Long establishmentDate) {
        Map<String, Object> body = new HashMap<>();
        body.put("ownerId", ownerId);
        body.put("relatedUserId", relatedUserId);
        body.put("blockDate", isoTimestamp(blockDate));
        body.put("establishmentDate", isoTimestamp(establishmentDate));
        try {
            restClient.post()
                    .uri("/users/relationships")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            log.warn("建 Turms 关系失败：ownerId={} relatedUserId={}", ownerId, relatedUserId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /**
     * 关系投影：改一行。**清空拉黑必须传 epoch-0**：Turms 的 `setOrUnsetDate` 对 null 是 no-op，
     * 且「全是 null」会被服务层短路（docs/truth/backend/projection.md）。
     */
    public void updateRelationship(long ownerId, long relatedUserId, Long blockDate, Long establishmentDate) {
        Map<String, Object> body = new HashMap<>();
        body.put("blockDate", isoTimestamp(blockDate));
        body.put("establishmentDate", isoTimestamp(establishmentDate));
        try {
            restClient.put()
                    .uri(uri -> uri.path("/users/relationships")
                            .queryParam("keys[0].ownerId", ownerId)
                            .queryParam("keys[0].relatedUserId", relatedUserId)
                            .build())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            log.warn("改 Turms 关系失败：ownerId={} relatedUserId={}", ownerId, relatedUserId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** 关系投影：批量删行（`DELETE /relationships` 收 `List<Key>`）。 */
    public void deleteRelationships(List<long[]> keys) {
        try {
            restClient.delete()
                    .uri(uri -> {
                        uri.path("/users/relationships");
                        for (int i = 0; i < keys.size(); i++) {
                            uri.queryParam("keys[" + i + "].ownerId", keys.get(i)[0])
                                    .queryParam("keys[" + i + "].relatedUserId", keys.get(i)[1]);
                        }
                        return uri.build();
                    })
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            log.warn("删 Turms 关系失败：keys={}", keys.size(), e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** 账号投影：Turms 里有没有这个用户（`GET /users?ids=`）；查不到时 Admin 回 204 空 body。 */
    public boolean userExists(long accountId) {
        try {
            JsonNode body = restClient.get()
                    .uri(uri -> uri.path("/users").queryParam("ids", accountId).build())
                    .retrieve()
                    .body(JsonNode.class);
            JsonNode data = body == null ? null : body.path("data");
            return data != null && data.isArray() && !data.isEmpty();
        } catch (RestClientException e) {
            log.warn("查 Turms 用户失败：accountId={}", accountId, e);
            throw ApiException.upstreamUnavailable();
        }
    }

    /** Turms 关系行：`blockDate` 非空表示拉黑，`establishmentDate` 是成为好友的时间。 */
    public record Relationship(long ownerId, long relatedUserId, String blockDate, String establishmentDate) {
    }

    private static String dateOrNull(JsonNode node) {
        return node == null || node.isNull() || node.isMissingNode() ? null : node.asString();
    }

    private static String isoTimestamp(Long epochMillis) {
        return epochMillis == null ? null : Instant.ofEpochMilli(epochMillis).toString();
    }

    /**
     * 代写「本人该会话的已读时间」：Admin `PUT /conversations`，`readDate` 传 null 让 Turms 取服务端当前时间。
     * 私聊键的 owner 必须是调用者本人（写反会把已读写到对端）；群侧 groupId 必须是 Turms 的 group id。
     * 复合主键入参形状 `keys[0].*` 与 `removeGroupMember` 同一套，冒烟已实测。
     */
    public void updateReadDate(long accountId, boolean groupMessage, long targetId) {
        // readDate 明确写 null：Turms 用服务端时间，一次拿到「现在 + 私聊只前进 + 群侧覆盖」
        Map<String, Object> body = new HashMap<>();
        body.put("readDate", null);
        try {
            restClient.put()
                    .uri(uri -> {
                        uri.path("/conversations");
                        if (groupMessage) {
                            return uri.queryParam("groupConversationMemberKeys[0].groupId", targetId)
                                    .queryParam("groupConversationMemberKeys[0].memberId", accountId)
                                    .build();
                        }
                        return uri.queryParam("privateConversationKeys[0].ownerId", accountId)
                                .queryParam("privateConversationKeys[0].targetId", targetId)
                                .build();
                    })
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .toBodilessEntity();
        } catch (RestClientException e) {
            // 没拿到确认就回 503：客户端据此保留未读，不假装清掉了
            log.warn("代写已读时间失败：accountId={} groupMessage={} targetId={}",
                    accountId, groupMessage, targetId, e);
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
