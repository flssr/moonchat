package im.moonchat.biz.controller.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;
import im.moonchat.biz.service.account.AccountService;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * #3 换 Turms 凭据。两种请求形态恰好一种（docs/truth/backend/identity.md）：
 * 带登录 JWT + `account_id` 是归属者切账号，不带认证头 + `account_key` 是 agent 换凭据。
 */
@RestController
@RequestMapping("/api/sessions")
@RequiredArgsConstructor
public class SessionController {

    private final AccountService accountService;

    @PostMapping
    public AccountResponses.SessionResponse create(Optional<CurrentAccount> me,
            @RequestBody AccountRequests.SessionRequest request) {
        return accountService.issueSession(me, request);
    }
}
