package im.moonchat.biz.controller.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;
import im.moonchat.biz.service.account.AccountService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** #3 换 Turms 凭据。S1 只做归属者形态，账号密钥形态随 S2 的建 agent 一起来。 */
@RestController
@RequestMapping("/api/sessions")
public class SessionController {

    private final AccountService accountService;

    public SessionController(AccountService accountService) {
        this.accountService = accountService;
    }

    @PostMapping
    public AccountResponses.SessionResponse create(CurrentAccount me,
            @RequestBody AccountRequests.SessionRequest request) {
        return accountService.issueSession(me, request);
    }
}
