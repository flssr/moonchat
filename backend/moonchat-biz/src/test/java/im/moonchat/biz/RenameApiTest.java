package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.sql.Timestamp;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/** #6 改名：同一事务写库并在事务内同步 Turms，没拿到确认就整笔回滚。 */
class RenameApiTest extends ApiTestSupport {

    @Test
    void 改名把新名字写进库并同步进Turms() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(patch("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"  新名字  "}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(me.accountId()))
                .andExpect(jsonPath("$.display_name").value("新名字"))
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
    void agent用自己的密钥也能改自己名字() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "旧名字");

        mockMvc.perform(patch("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"新名字"}
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

        mockMvc.perform(patch("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"改不动的名字"}
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
    void 冻结账号不能改名() throws Exception {
        Caller me = newCaller();
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        mockMvc.perform(patch("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"冻结了"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
    }

    @Test
    void 空白名字与缺凭据() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(patch("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":" "}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("display_name"));

        mockMvc.perform(patch("/api/accounts/me")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"display_name":"没凭据"}
                                """))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }
}
