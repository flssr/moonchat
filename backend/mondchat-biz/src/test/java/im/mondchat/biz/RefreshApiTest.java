package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.nimbusds.jwt.JWTClaimsSet;
import java.time.Duration;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

/** #20 登录 JWT 滑动续期：无状态、账号不变、只换登录凭据。 */
class RefreshApiTest extends ApiTestSupport {

    @Test
    void 续期后仍是同一个账号且拿到新凭据() throws Exception {
        Caller me = newCaller();

        String body = mockMvc.perform(post("/api/auth/refresh")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account.account_id").value(me.accountId()))
                .andExpect(jsonPath("$.account.type").value("human"))
                .andReturn().getResponse().getContentAsString();

        String refreshed = tokenOf(body);
        JWTClaimsSet claims = loginClaims(refreshed);
        assertThat(claims.getSubject()).isEqualTo(Long.toString(me.accountId()));
        assertThat(claims.getExpirationTime().toInstant()).isBetween(
                Instant.now().plus(Duration.ofDays(7)).minusSeconds(5),
                Instant.now().plus(Duration.ofDays(7)));
    }

    @Test
    void 无效凭据与缺失凭据都是未认证() throws Exception {
        mockMvc.perform(post("/api/auth/refresh")
                        .header(HttpHeaders.AUTHORIZATION, bearer("not-a-jwt")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));

        mockMvc.perform(post("/api/auth/refresh"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }

    @Test
    void 冻结账号不能续期() throws Exception {
        Caller me = newCaller();
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        mockMvc.perform(post("/api/auth/refresh")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));
    }
}
