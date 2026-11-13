package im.moonchat.biz;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/**
 * 账号级限流桶：只对 `agent` 来源的好友申请生效，校验先于桶（docs/agent-connection.md 的「限流与来源」）。
 * 测试把速率配成 3，见 {@link TestStack#ACCOUNT_RATE_PER_MINUTE}。
 */
class RateLimitApiTest extends ApiTestSupport {

    private static final int LIMIT = TestStack.ACCOUNT_RATE_PER_MINUTE;

    @Test
    void agent超过账号级桶返回限流() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "刷屏的");

        for (int i = 0; i < LIMIT; i++) {
            requestFriend(agent.accountKey(), newCaller().accountId())
                    .andExpect(status().isCreated());
        }

        requestFriend(agent.accountKey(), newCaller().accountId())
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("rate_limited"));
    }

    @Test
    void 同账号的真人来源不进任何桶() throws Exception {
        Caller me = newCaller();

        for (int i = 0; i <= LIMIT; i++) {
            requestFriend(me.token(), newCaller().accountId())
                    .andExpect(status().isCreated());
        }
    }

    @Test
    void 校验先于桶所以不存在的对端仍是未找到() throws Exception {
        Caller owner = newCaller();
        Agent agent = newAgent(owner, "刷屏的");

        for (int i = 0; i < LIMIT; i++) {
            requestFriend(agent.accountKey(), newCaller().accountId())
                    .andExpect(status().isCreated());
        }

        requestFriend(agent.accountKey(), 99999999)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
    }

    private org.springframework.test.web.servlet.ResultActions requestFriend(String credential, long peerAccountId)
            throws Exception {
        return mockMvc.perform(post("/api/friendships")
                .header(HttpHeaders.AUTHORIZATION, bearer(credential))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"peer_account_id":%d}
                        """.formatted(peerAccountId)));
    }
}
