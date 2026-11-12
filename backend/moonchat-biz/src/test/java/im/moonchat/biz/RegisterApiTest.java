package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

/** #1 注册：两行同事务、Turms 用户按这个 id 建、失败回滚、入口校验。 */
class RegisterApiTest extends ApiTestSupport {

    @Test
    void 注册写两行并把同步状态置为synced() throws Exception {
        String email = uniqueEmail();
        String body = register(email, "secret123", "小明");

        long accountId = ((Number) JsonPath.read(body, "$.account_id")).longValue();
        assertThat(JsonPath.read(body, "$.type").toString()).isEqualTo("human");

        assertThat(jdbc.queryForObject("select type from account where id = ?", String.class, accountId))
                .isEqualTo("human");
        assertThat(jdbc.queryForObject("select owner_account_id from account where id = ?", Long.class, accountId))
                .isNull();
        assertThat(jdbc.queryForObject("select turms_sync_state from account where id = ?", String.class, accountId))
                .isEqualTo("synced");
        assertThat(jdbc.queryForObject("select display_name from account_info where account_id = ?", String.class, accountId))
                .isEqualTo("小明");
        assertThat(jdbc.queryForObject("select credential_hash from account_info where account_id = ?", String.class, accountId))
                .startsWith("bcrypt$2a$10$");
    }

    @Test
    void 注册把邮箱归一后入库并按同一个id建用户() throws Exception {
        String rawEmail = "  MiXeD" + System.nanoTime() + "@Example.COM ";
        String body = register(rawEmail, "secret123", "阿吉");
        long accountId = ((Number) JsonPath.read(body, "$.account_id")).longValue();

        assertThat(jdbc.queryForObject("select email from account_info where account_id = ?", String.class, accountId))
                .isEqualTo(rawEmail.trim().toLowerCase());

        assertThat(TestStack.TURMS_ADMIN.lastPath()).isEqualTo("/users");
        assertThat(TestStack.TURMS_ADMIN.lastAuthorization()).isEqualTo("Basic "
                + Base64.getEncoder().encodeToString("turms:turms".getBytes(StandardCharsets.UTF_8)));
        String turmsUser = TestStack.TURMS_ADMIN.lastBody();
        assertThat(((Number) JsonPath.read(turmsUser, "$.id")).longValue()).isEqualTo(accountId);
        assertThat(JsonPath.read(turmsUser, "$.name").toString()).isEqualTo("阿吉");
        assertThat(JsonPath.read(turmsUser, "$.password").toString().length()).isBetween(1, 16);
    }

    @Test
    void 邮箱已被注册返回冲突() throws Exception {
        String email = uniqueEmail();
        register(email, "secret123", "第一个");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"secret123","display_name":"第二个"}
                                """.formatted(email)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("conflict"));
    }

    @Test
    void 建Turms用户失败时连同账号行一起回滚() throws Exception {
        TestStack.TURMS_ADMIN.respondWith(500);
        String email = uniqueEmail();

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"secret123","display_name":"孤儿"}
                                """.formatted(email)))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("upstream_unavailable"));

        assertThat(jdbc.queryForObject("select count(*) from account_info where email = ?", Long.class, email))
                .isZero();
    }

    @Test
    void 入口校验拦下密码纯数字与过短() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"12345678","display_name":"纯数字"}
                                """.formatted(uniqueEmail())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("password"));

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"short7!","display_name":"太短"}
                                """.formatted(uniqueEmail())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("password"));
    }

    @Test
    void 入口校验拦下名字超长与邮箱形状() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"secret123","display_name":"%s"}
                                """.formatted(uniqueEmail(), "名".repeat(21))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("display_name"));

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"nope","password":"secret123","display_name":"邮箱错"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.field").value("email"));
    }
}
