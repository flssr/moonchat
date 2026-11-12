package im.moonchat.biz;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

/** #4 我的账号：自己排第一，名下的 agent 按创建时间升序。 */
class MineApiTest extends ApiTestSupport {

    @Test
    void 自己排第一且名下的agent按创建时间升序() throws Exception {
        Caller me = newCaller();
        Instant now = Instant.now();
        long laterAgent = insertAgent(me.accountId(), "晚建的", now.minus(Duration.ofHours(1)));
        long earlierAgent = insertAgent(me.accountId(), "早建的", now.minus(Duration.ofHours(2)));
        insertAgent(newCaller().accountId(), "别人家的", now);

        mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(3))
                .andExpect(jsonPath("$.items[0].account_id").value(me.accountId()))
                .andExpect(jsonPath("$.items[0].type").value("human"))
                .andExpect(jsonPath("$.items[1].account_id").value(earlierAgent))
                .andExpect(jsonPath("$.items[1].type").value("agent"))
                .andExpect(jsonPath("$.items[2].account_id").value(laterAgent));
    }

    @Test
    void 建出来的agent出现在我的账号列表里() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        mockMvc.perform(get("/api/accounts/mine")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].account_id").value(me.accountId()))
                .andExpect(jsonPath("$.items[1].account_id").value(agent.accountId()))
                .andExpect(jsonPath("$.items[1].type").value("agent"))
                .andExpect(jsonPath("$.items[1].display_name").value("小助手"));
    }

    @Test
    void 没有凭据返回未认证() throws Exception {
        mockMvc.perform(get("/api/accounts/mine"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }
}
