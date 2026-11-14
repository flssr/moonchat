package im.mondchat.biz;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * 假的 Turms Admin：实现 im-facade 会打的那几条 RestClient 调用——建用户、改名、建群、成员集合查询与增删。
 * 群与成员集合是有状态的（`groupMembers`），所以投影对账能真的被验到；Turms 自己是否认这份数据，
 * 仍由 `infra/turms/smoke` 的脚本断言。
 */
final class FakeTurmsAdmin {

    private static final JsonMapper JSON = JsonMapper.builder().build();

    /** Turms 的 group id 是雪花值，比 Number.MAX_SAFE_INTEGER 还大；Biz 侧是 long，照收。 */
    private static final long FIRST_GROUP_ID = 900000000000000000L;

    private final HttpServer server;
    private final AtomicLong nextGroupId = new AtomicLong(FIRST_GROUP_ID);
    private final Map<Long, Set<Long>> groupMembers = new ConcurrentHashMap<>();

    private volatile int status = 200;
    private volatile String lastMethod;
    private volatile String lastPath;
    private volatile String lastQuery;
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
        lastMethod = null;
        lastPath = null;
        lastQuery = null;
        lastBody = null;
        lastAuthorization = null;
        return this;
    }

    /** 让下一次调用失败，用来验「建用户失败要连同账号行回滚」与「投影失败留在 pending」。 */
    FakeTurmsAdmin respondWith(int statusCode) {
        this.status = statusCode;
        return this;
    }

    /** Turms 侧某个群的成员集合：测试拿它和 `room_member` 的有效行逐条比。 */
    Set<Long> membersOf(long turmsGroupId) {
        return groupMembers.getOrDefault(turmsGroupId, Set.of());
    }

    int groupCount() {
        return groupMembers.size();
    }

    /** 模拟 Turms 把群弄丢了：投影下次重算时应按 PG 重建。 */
    void forgetGroup(long turmsGroupId) {
        groupMembers.remove(turmsGroupId);
    }

    String lastMethod() {
        return lastMethod;
    }

    String lastPath() {
        return lastPath;
    }

    String lastQuery() {
        return lastQuery;
    }

    String lastBody() {
        return lastBody;
    }

    String lastAuthorization() {
        return lastAuthorization;
    }

    private void handle(com.sun.net.httpserver.HttpExchange exchange) throws IOException {
        lastMethod = exchange.getRequestMethod();
        lastPath = exchange.getRequestURI().getPath();
        lastQuery = exchange.getRequestURI().getQuery();
        lastAuthorization = exchange.getRequestHeaders().getFirst("Authorization");
        lastBody = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        if (status != 200) {
            exchange.sendResponseHeaders(status, -1);
            exchange.close();
            return;
        }

        String body = switch (lastMethod + " " + lastPath) {
            case "POST /groups" -> createGroup(lastBody);
            case "GET /groups" -> queryGroups(lastQuery);
            case "GET /groups/members/page" -> queryMembersPage(lastQuery);
            case "POST /groups/members" -> addGroupMember(lastBody);
            case "DELETE /groups/members" -> removeGroupMember(lastQuery);
            default -> null;
        };
        // 查不到时 Turms 回 204 无 body（NO_CONTENT），写接口回 200 无 body
        if (body != null) {
            exchange.getResponseHeaders().add("Content-Type", "application/json");
        }
        exchange.sendResponseHeaders(body == null ? 204 : 200, body == null ? -1 : 0);
        if (body != null) {
            exchange.getResponseBody().write(body.getBytes(StandardCharsets.UTF_8));
        }
        exchange.close();
    }

    private String createGroup(String body) {
        JsonNode json = JSON.readTree(body);
        long groupId = nextGroupId.incrementAndGet();
        Set<Long> members = ConcurrentHashMap.newKeySet();
        members.add(json.path("creatorId").asLong());
        groupMembers.put(groupId, members);
        return "{\"code\":1000,\"data\":{\"id\":" + groupId
                + ",\"name\":\"" + json.path("name").asString() + "\"}}";
    }

    private String queryGroups(String query) {
        Long groupId = firstGroupId(query);
        return groupMembers.containsKey(groupId)
                ? "{\"code\":1000,\"data\":[{\"id\":" + groupId + "}]}"
                : null;
    }

    private String queryMembersPage(String query) {
        Map<String, String> params = params(query);
        Long groupId = Long.valueOf(params.get("groupIds"));
        List<Long> members = new ArrayList<>(groupMembers.getOrDefault(groupId, Set.of()));
        members.sort(Long::compare);
        int size = Integer.parseInt(params.getOrDefault("size", "1000"));
        int page = Integer.parseInt(params.getOrDefault("page", "0"));
        int from = Math.min(page * size, members.size());
        int to = Math.min(from + size, members.size());

        StringBuilder records = new StringBuilder();
        for (long accountId : members.subList(from, to)) {
            records.append(records.isEmpty() ? "" : ",")
                    .append("{\"key\":{\"groupId\":").append(groupId)
                    .append(",\"userId\":").append(accountId).append("},\"role\":\"MEMBER\"}");
        }
        return "{\"code\":1000,\"data\":{\"total\":" + members.size() + ",\"records\":[" + records + "]}}";
    }

    private String addGroupMember(String body) {
        JsonNode json = JSON.readTree(body);
        long groupId = json.path("groupId").asLong();
        groupMembers.computeIfAbsent(groupId, key -> new LinkedHashSet<>())
                .add(json.path("userId").asLong());
        return "{\"code\":1000,\"data\":{\"key\":{\"groupId\":" + groupId + "}}}";
    }

    private String removeGroupMember(String query) {
        Map<String, String> params = params(query);
        groupMembers.computeIfAbsent(Long.valueOf(params.get("keys[0].groupId")), key -> new LinkedHashSet<>())
                .remove(Long.valueOf(params.get("keys[0].userId")));
        return "{\"code\":1000,\"data\":{\"deletedCount\":1}}";
    }

    private Long firstGroupId(String query) {
        return Long.valueOf(params(query).get("ids"));
    }

    /** 查询串按 `&` 切开再解码：`keys[0].groupId` 这类带方括号的键也要读得回来。 */
    private static Map<String, String> params(String query) {
        Map<String, String> params = new HashMap<>();
        if (query == null) {
            return params;
        }
        for (String pair : query.split("&")) {
            int split = pair.indexOf('=');
            if (split > 0) {
                params.put(URLDecoder.decode(pair.substring(0, split), StandardCharsets.UTF_8),
                        URLDecoder.decode(pair.substring(split + 1), StandardCharsets.UTF_8));
            }
        }
        return params;
    }
}
