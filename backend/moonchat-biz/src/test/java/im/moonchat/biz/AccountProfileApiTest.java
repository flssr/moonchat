package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * #24 本人资料与 #6 改资料的资料部分（docs/truth/backend/identity.md）：
 * `GET /api/accounts/me` 回填、`PUT /api/accounts/me` 按全量提交语义保存，
 * 资料字段只出现在这两处——资料页、登录、切账号、我的账号都不带。
 */
class AccountProfileApiTest extends ApiTestSupport {

    @Test
    void 新注册账号的默认性别是private而生日未设置() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(get("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(me.accountId()))
                .andExpect(jsonPath("$.display_name").value("路人"))
                // DDL 的 default 'private'：注册路径不写这一列
                .andExpect(jsonPath("$.gender").value("private"))
                .andExpect(jsonPath("$.birthday").isEmpty())
                .andExpect(jsonPath("$.updated_at").exists());
    }

    @Test
    void agent用密钥也能读自己的资料且默认值一致() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "小助手");

        mockMvc.perform(get("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(agent.accountId()))
                .andExpect(jsonPath("$.display_name").value("小助手"))
                .andExpect(jsonPath("$.gender").value("private"))
                .andExpect(jsonPath("$.birthday").isEmpty());
    }

    @Test
    void 没凭据读自己的资料是401() throws Exception {
        mockMvc.perform(get("/api/accounts/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }

    @Test
    void 三条账号路由互不抢路() throws Exception {
        Caller me = newCaller();
        Caller other = newCaller();

        // /me 是本人资料
        mockMvc.perform(get("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(me.accountId()));

        // /mine 仍是列表（自己 + 名下 agent）
        mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].account_id").value(me.accountId()));

        // /{accountId} 仍是资料页，且不含性别生日
        mockMvc.perform(get("/api/accounts/" + other.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(other.accountId()))
                .andExpect(jsonPath("$.gender").doesNotExist())
                .andExpect(jsonPath("$.birthday").doesNotExist());
    }

    @Test
    void birthday传null时清掉已设置的生日() throws Exception {
        Caller me = newCaller();
        saveProfile(me, "路人", "female", "1995-03-04")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.birthday").value("1995-03-04"));

        saveProfile(me, "路人", "female", null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.birthday").isEmpty());

        mockMvc.perform(get("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(jsonPath("$.birthday").isEmpty())
                .andExpect(jsonPath("$.gender").value("female"));
    }

    @Test
    void 日历上不存在的日期与未来日期都指回birthday() throws Exception {
        Caller me = newCaller();

        saveProfile(me, "路人", "private", "2026-02-31")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("birthday"));

        saveProfile(me, "路人", "private", LocalDate.now().plusDays(1).toString())
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("birthday"));
    }

    @Test
    void 性别不在枚举内与生日的形状不对各有自己的field() throws Exception {
        Caller me = newCaller();

        saveProfile(me, "路人", "unknown", "1995-03-04")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("gender"));

        saveProfile(me, "路人", "private", "1995/03/04")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("birthday"));
    }

    @Test
    void 鉴权与列表响应都不带资料字段() throws Exception {
        Caller me = newCaller();
        String email = jdbc.queryForObject("select email from account_info where account_id = ?",
                String.class, me.accountId());

        // 登录只回鉴权字段，资料走 GET /api/accounts/me
        assertThat(loginBody(email, "secret123")).doesNotContain("gender").doesNotContain("birthday");

        String mine = mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(mine).doesNotContain("gender").doesNotContain("birthday");

        String session = mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(me.accountId())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(session).doesNotContain("gender").doesNotContain("birthday");
    }

    private org.springframework.test.web.servlet.ResultActions saveProfile(Caller me, String name, String gender,
            String birthday) throws Exception {
        String birthdayJson = birthday == null ? "null" : "\"" + birthday + "\"";
        return mockMvc.perform(put("/api/accounts/me")
                .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"display_name":"%s","gender":"%s","birthday":%s}
                        """.formatted(name, gender, birthdayJson)));
    }
}
