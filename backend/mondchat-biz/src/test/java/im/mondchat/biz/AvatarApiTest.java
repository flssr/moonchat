package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/**
 * issue #10：头像变成服务端真相。平台默认头像的 key 落在 `account_info.avatar`，
 * 登录 / 换凭据 / 我的账号 / 资料页 / 好友列表 / 群成员都带 `avatar`；不做上传、不投影 Turms。
 */
class AvatarApiTest extends ApiTestSupport {

    private static final List<String> AGENT_AVATARS = List.of("agent_blue", "agent_pink", "agent_gold");

    @Test
    void 真人选完头像后各个读接口都带上它() throws Exception {
        Caller me = newCaller();
        Caller friend = newCaller();
        befriend(me, friend);

        putAvatar(me.token(), "female_02")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").value("female_02"));

        // #24 本人资料
        mockMvc.perform(get("/api/accounts/me").header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").value("female_02"));

        // #4 我的账号
        mockMvc.perform(get("/api/accounts/mine").header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].account_id").value(me.accountId()))
                .andExpect(jsonPath("$.items[0].avatar").value("female_02"));

        // #7 资料页（好友视角）
        mockMvc.perform(get("/api/accounts/" + me.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(friend.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").value("female_02"));

        // #8 好友列表（好友视角）
        mockMvc.perform(get("/api/friendships").param("status", "accepted")
                        .header(HttpHeaders.AUTHORIZATION, bearer(friend.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].peer_account_id").value(me.accountId()))
                .andExpect(jsonPath("$.items[0].avatar").value("female_02"));

        // #2 登录
        assertThat(loginBody(emailOf(me.accountId()), "secret123")).contains("\"avatar\":\"female_02\"");

        // #3 换 Turms 凭据
        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(me.accountId())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").value("female_02"));

        // #15 群成员（房主先进，取 items[0]）
        long roomId = createRoom(me, "头像群", friend);
        mockMvc.perform(get("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(friend.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].account_id").value(me.accountId()))
                .andExpect(jsonPath("$.items[0].avatar").value("female_02"));
    }

    @Test
    void 头像key只认平台这一套且按账号类型分开() throws Exception {
        Caller me = newCaller();

        // 不在这一套 key 里：bean validation 直接挡，field 指回 avatar
        putAvatar(me.token(), "uploaded.png")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("avatar"));
        // 真人不能用 agent 那三张
        putAvatar(me.token(), "agent_blue")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("avatar"));
        assertThat(avatarColumn(me.accountId())).isNull();

        // agent 反过来也不能用真人那 6 张
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");
        putAvatar(agent.accountKey(), "male_01")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("avatar"));
        putAvatar(agent.accountKey(), "agent_gold")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").value("agent_gold"));
        assertThat(avatarColumn(agent.accountId())).isEqualTo("agent_gold");
    }

    @Test
    void 头像传null清回生成的首字头像() throws Exception {
        Caller me = newCaller();

        putAvatar(me.token(), "male_02")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").value("male_02"));
        assertThat(avatarColumn(me.accountId())).isEqualTo("male_02");

        putAvatar(me.token(), null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").isEmpty());
        assertThat(avatarColumn(me.accountId())).isNull();

        mockMvc.perform(get("/api/accounts/me").header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatar").isEmpty());
    }

    @Test
    void 新建的agent自带一枚默认agent头像() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");

        String mine = mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        List<String> avatars = JsonPath.read(mine, "$.items[*].avatar");
        assertThat(avatars).contains(AGENT_AVATARS.get((int) (agent.accountId() % AGENT_AVATARS.size())));
    }

    private ResultActions putAvatar(String token, String avatar) throws Exception {
        String value = avatar == null ? "null" : "\"" + avatar + "\"";
        return mockMvc.perform(put("/api/accounts/me/avatar")
                .header(HttpHeaders.AUTHORIZATION, bearer(token))
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"avatar\":" + value + "}"));
    }

    private String avatarColumn(long accountId) {
        return jdbc.queryForObject("select avatar from account_info where account_id = ?",
                String.class, accountId);
    }

    private String emailOf(long accountId) {
        return jdbc.queryForObject("select email from account_info where account_id = ?",
                String.class, accountId);
    }

    /** 两人互为好友：a 申请、b 同意。 */
    private void befriend(Caller a, Caller b) throws Exception {
        mockMvc.perform(post("/api/friendships")
                        .header(HttpHeaders.AUTHORIZATION, bearer(a.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"peer_account_id":%d}
                                """.formatted(b.accountId())))
                .andExpect(status().isCreated());
        mockMvc.perform(post("/api/friendships/" + a.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(b.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"accept"}
                                """))
                .andExpect(status().isOk());
    }

    /** 建群并把好友拉进来：房主先入群，成员列表里他是 items[0]。 */
    private long createRoom(Caller owner, String name, Caller member) throws Exception {
        String body = mockMvc.perform(post("/api/rooms")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s"}
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long roomId = ((Number) JsonPath.read(body, "$.room_id")).longValue();
        mockMvc.perform(post("/api/rooms/" + roomId + "/members")
                        .header(HttpHeaders.AUTHORIZATION, bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(member.accountId())))
                .andExpect(status().isCreated());
        return roomId;
    }
}
