package im.moonchat.biz.account;

import im.moonchat.biz.auth.CurrentAccount;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** #4 我的账号 + 我名下的 agent（切账号入口的数据源）。 */
@RestController
@RequestMapping("/api/accounts")
public class AccountController {

    private final AccountService accounts;

    AccountController(AccountService accounts) {
        this.accounts = accounts;
    }

    @GetMapping("/mine")
    public AccountDtos.MineResponse mine(CurrentAccount me) {
        return accounts.mine(me);
    }
}
