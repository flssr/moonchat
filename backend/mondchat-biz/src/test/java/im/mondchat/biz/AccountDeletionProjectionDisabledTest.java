package im.mondchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import im.mondchat.biz.config.ProjectionProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

/** 派发关闭时不能先硬删 PG，否则 Turms 用户与群成员会永久失去清理入口。 */
class AccountDeletionProjectionDisabledTest extends ApiTestSupport {

    @MockitoBean
    ProjectionProperties projectionProperties;

    @BeforeEach
    void disableProjection() {
        when(projectionProperties.enabled()).thenReturn(false);
    }

    @Test
    void 投影关闭时注销返回503且不删账号() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(delete("/api/accounts/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"password":"secret123"}
                                """))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("projection_disabled"));

        assertThat(jdbc.queryForObject("select count(*) from account where id = ?", Long.class, me.accountId()))
                .isEqualTo(1);
    }
}
