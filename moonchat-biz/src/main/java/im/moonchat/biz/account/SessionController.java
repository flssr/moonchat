package im.moonchat.biz.account;

import im.moonchat.biz.auth.CurrentAccount;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** #3 换 Turms 凭据。S1 只做归属者形态，账号密钥形态随 S2 的建 agent 一起来。 */
@RestController
@RequestMapping("/api/sessions")
public class SessionController {

    private final AccountService accounts;

    SessionController(AccountService accounts) {
        this.accounts = accounts;
    }

    @PostMapping
    public AccountDtos.SessionResponse create(CurrentAccount me, @RequestBody AccountDtos.SessionRequest request) {
        return accounts.issueSession(me, request);
    }
}
