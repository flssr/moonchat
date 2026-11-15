package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.sql.Timestamp;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * #6 改资料（`PUT`，三字段全量提交）：同一事务写库，名字变了才在事务内同步 Turms，
 * 没拿到确认就整笔回滚。只传 `display_name` 的旧调用方式已不兼容，回 400。
 */
class RenameApiTest extends ApiTestSupport {

    @Test
    void 改名把新名字写进库并同步进Turms() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"  新名字  ","gender":"female","birthday":"1990-05-20"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(me.accountId()))
                .andExpect(jsonPath("$.display_name").value("新名字"))
                .andExpect(jsonPath("$.gender").value("female"))
                .andExpect(jsonPath("$.birthday").value("1990-05-20"))
                .andExpect(jsonPath("$.updated_at").exists());

        assertThat(jdbc.queryForObject("select display_name from account_info where account_id = ?",
                String.class, me.accountId()))
                .isEqualTo("新名字");
        assertThat(jdbc.queryForObject("select turms_sync_state from account where id = ?",
                String.class, me.accountId()))
                .isEqualTo("synced");

        assertThat(TestStack.TURMS_ADMIN.lastMethod()).isEqualTo("PUT");
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isEqualTo("/users");
        assertThat(TestStack.TURMS_ADMIN.lastQuery()).isEqualTo("ids=" + me.accountId());
        assertThat(JsonPath.read(TestStack.TURMS_ADMIN.lastBody(), "$.name").toString()).isEqualTo("新名字");
    }

    @Test
    void 名字没变时不碰Turms而且同步状态不变() throws Exception {
        Caller me = newCaller();
        String syncBefore = jdbc.queryForObject("select turms_sync_state from account where id = ?",
                String.class, me.accountId());
        // 注册本身会调一次 Turms 建用户：先清干净，再断言这次保存一次都没调
        TestStack.TURMS_ADMIN.reset();

        mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"路人","gender":"male","birthday":"2000-01-01"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.display_name").value("路人"))
                .andExpect(jsonPath("$.gender").value("male"));

        // 只是改资料，名字没变：Turms 与同步状态都不该被碰
        assertThat(TestStack.TURMS_ADMIN.lastPath()).isNull();
        assertThat(jdbc.queryForObject("select turms_sync_state from account where id = ?",
                String.class, me.accountId())).isEqualTo(syncBefore);
        assertThat(jdbc.queryForObject("select birthday from account_info where account_id = ?",
                java.sql.Date.class, me.accountId()).toString()).isEqualTo("2000-01-01");
    }

    @Test
    void agent用自己的密钥也能改自己资料() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "旧名字");

        mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"新名字","gender":"private","birthday":null}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(agent.accountId()));

        assertThat(jdbc.queryForObject("select display_name from account_info where account_id = ?",
                String.class, agent.accountId()))
                .isEqualTo("新名字");
    }

    @Test
    void 同步失败时名字与状态都不变() throws Exception {
        Caller me = newCaller();
        Timestamp before = jdbc.queryForObject("select updated_at from account where id = ?",
                Timestamp.class, me.accountId());
        TestStack.TURMS_ADMIN.respondWith(500);

        mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"改不动的名字","gender":"private","birthday":null}
                                """))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));

        assertThat(jdbc.queryForObject("select display_name from account_info where account_id = ?",
                String.class, me.accountId()))
                .isEqualTo("路人");
        assertThat(jdbc.queryForObject("select turms_sync_state from account where id = ?",
                String.class, me.accountId()))
                .isEqualTo("synced");
        assertThat(jdbc.queryForObject("select updated_at from account where id = ?",
                Timestamp.class, me.accountId()))
                .isEqualTo(before);
    }

    @Test
    void 冻结账号不能改资料() throws Exception {
        Caller me = newCaller();
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"冻结了","gender":"private","birthday":null}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
    }

    @Test
    void 只传名字的旧调用方式回400且field指到缺的字段() throws Exception {
        Caller me = newCaller();

        String body = mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"只有名字"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);

        // 缺 gender 与 birthday 两个：只报其中一条，先后不保证，别把顺序钉进测试
        assertThat(JsonPath.<String>read(body, "$.field")).isIn("gender", "birthday");
    }

    @Test
    void 空白名字与缺凭据() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(put("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":" ","gender":"private","birthday":null}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("display_name"));

        mockMvc.perform(put("/api/accounts/me")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"没凭据","gender":"private","birthday":null}
                                """))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }
}
