package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jwt.JWTClaimsSet;
import java.time.Duration;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

/** #2 登录：换登录 JWT，不签发 Turms 凭据。 */
class LoginApiTest extends ApiTestSupport {

    @Test
    void 登录返回七天有效的登录凭据与账号回显() throws Exception {
        String email = uniqueEmail();
        long accountId = ((Number) JsonPath.read(register(email, "secret123", "小明"), "$.account_id")).longValue();

        String body = loginBody(email, "secret123");

        assertThat(accountIdOf(body)).isEqualTo(accountId);
        assertThat(JsonPath.read(body, "$.account.display_name").toString()).isEqualTo("小明");
        assertThat(JsonPath.read(body, "$.account.type").toString()).isEqualTo("human");

        JWTClaimsSet claims = loginClaims(tokenOf(body));
        assertThat(claims.getSubject()).isEqualTo(Long.toString(accountId));
        Instant expiresAt = claims.getExpirationTime().toInstant();
        assertThat(expiresAt).isBetween(
                Instant.now().plus(Duration.ofDays(7)).minusSeconds(5),
                Instant.now().plus(Duration.ofDays(7)));
    }

    @Test
    void 账号不存在与密码错误返回同一个码() throws Exception {
        String email = uniqueEmail();
        register(email, "secret123", "小明");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"secret123"}
                                """.formatted(uniqueEmail())))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"%s","password":"wrong-pass"}
                                """.formatted(email)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }

    @Test
    void 缺字段返回校验失败() throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"password":"secret123"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("email"));
    }
}
