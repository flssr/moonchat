package im.mondchat.biz;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

/** #7 资料页：只有名字、账号 id、是否已是好友——非好友也看得到，这就是加好友的唯一入口。 */
class ProfileApiTest extends ApiTestSupport {

    @Test
    void 非好友也看得到名字与账号id但看不到别的字段() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();

        mockMvc.perform(get("/api/accounts/" + peer.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(peer.accountId()))
                .andExpect(jsonPath("$.display_name").value("路人"))
                .andExpect(jsonPath("$.is_friend").value(false))
                .andExpect(jsonPath("$.type").doesNotExist())
                .andExpect(jsonPath("$.email").doesNotExist())
                .andExpect(jsonPath("$.owner_account_id").doesNotExist());
    }

    @Test
    void 已是好友时is_friend为真() throws Exception {
        Caller me = newCaller();
        Caller peer = newCaller();
        long lower = Math.min(me.accountId(), peer.accountId());
        long higher = Math.max(me.accountId(), peer.accountId());
        jdbc.update("""
                insert into friendship (account_id, peer_account_id, status, requested_by)
                values (?, ?, 'accepted', ?)
                """, lower, higher, me.accountId());

        mockMvc.perform(get("/api/accounts/" + peer.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.is_friend").value(true));
    }

    @Test
    void 账号不存在返回未找到() throws Exception {
        Caller me = newCaller();

        mockMvc.perform(get("/api/accounts/99999999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(me.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("not_found"));
    }

    @Test
    void agent用密钥也能看资料页() throws Exception {
        Caller me = newCaller();
        Agent agent = newAgent(me, "小助手");

        mockMvc.perform(get("/api/accounts/" + me.accountId())
                        .header(HttpHeaders.AUTHORIZATION, bearer(agent.accountKey())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.account_id").value(me.accountId()));
    }

    @Test
    void 没凭据返回未认证() throws Exception {
        mockMvc.perform(get("/api/accounts/100000000"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthenticated"));
    }
}
