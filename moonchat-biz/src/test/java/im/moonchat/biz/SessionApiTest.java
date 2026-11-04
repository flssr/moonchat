package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/** #3 换 Turms 凭据：S1 只做归属者形态，凭据只授 QUERY。 */
class SessionApiTest extends ApiTestSupport {

    @Test
    void 归属者换到的Turms凭据只授查询且sub就是账号id() throws Exception {
        Caller me = newCaller();

        String body = mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"account_id\":" + me.accountId() + "}"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        assertThat(((Number) JsonPath.read(body, "$.account_id")).longValue()).isEqualTo(me.accountId());
        assertThat(((Number) JsonPath.read(body, "$.turms.user_id")).longValue()).isEqualTo(me.accountId());
        assertThat(JsonPath.read(body, "$.turms.gateway_url").toString()).isNotBlank();

        SignedJWT credential = SignedJWT.parse(JsonPath.read(body, "$.turms.credential"));
        assertThat(credential.getHeader().getAlgorithm()).isEqualTo(JWSAlgorithm.HS256);
        assertThat(credential.verify(new MACVerifier(Files.readAllBytes(TestStack.JWT_SECRET_FILE)))).isTrue();
        JWTClaimsSet claims = credential.getJWTClaimsSet();
        assertThat(claims.getSubject()).isEqualTo(Long.toString(me.accountId()));
        assertThat(claims.getBooleanClaim("authenticated")).isTrue();
        assertThat(claims.getClaim("statements")).isEqualTo(List.of(
                Map.of("effect", "ALLOW", "actions", List.of("QUERY"), "resources", List.of("*"))));
        assertThat(claims.getExpirationTime().toInstant()).isBetween(
                Instant.now().plus(Duration.ofHours(11)),
                Instant.now().plus(Duration.ofHours(12)));
    }

    @Test
    void 归属者能换到名下agent账号的凭据() throws Exception {
        Caller me = newCaller();
        long agentId = insertAgent(me.accountId(), "小助手", Instant.now());

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"account_id\":" + agentId + "}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(agentId))
                .andExpect(jsonPath("$.type").value("agent"))
                .andExpect(jsonPath("$.display_name").value("小助手"))
                .andExpect(jsonPath("$.turms.user_id").value(agentId));
    }

    @Test
    void 不在我名下的账号返回禁止() throws Exception {
        Caller me = newCaller();
        Caller other = newCaller();

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"account_id\":" + other.accountId() + "}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
    }

    @Test
    void 账号不存在返回未找到() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"account_id\":99999999}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
    }

    @Test
    void 冻结账号与缺account_id各有自己的码() throws Exception {
        Caller me = newCaller();
        jdbc.update("update account_info set status = 'frozen' where account_id = ?", me.accountId());

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"account_id\":" + me.accountId() + "}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_frozen"));

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("account_id"));
    }

    @Test
    void 账号密钥换到该账号的Turms凭据() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        String body = mockMvc.perform(post("/api/sessions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_key":"%s"}
                                """.formatted(agent.accountKey())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(agent.accountId()))
                .andExpect(jsonPath("$.type").value("agent"))
                .andExpect(jsonPath("$.display_name").value("小助手"))
                .andExpect(jsonPath("$.turms.user_id").value(agent.accountId()))
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        SignedJWT credential = SignedJWT.parse(JsonPath.read(body, "$.turms.credential"));
        assertThat(credential.getJWTClaimsSet().getSubject()).isEqualTo(Long.toString(agent.accountId()));
    }

    @Test
    void 乱写的密钥是未认证() throws Exception {
        mockMvc.perform(post("/api/sessions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_key":"not-a-real-key"}
                                """))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }

    @Test
    void 两种形态混用是校验失败() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d,"account_key":"%s"}
                                """.formatted(agent.accountId(), agent.accountKey())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("account_key"));
    }

    @Test
    void 缺凭据与两种形态都不给() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(post("/api/sessions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account_id":%d}
                                """.formatted(me.accountId())))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));

        mockMvc.perform(post("/api/sessions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"))
                .andExpect(jsonPath("$.field").value("account_id"));
    }
}
