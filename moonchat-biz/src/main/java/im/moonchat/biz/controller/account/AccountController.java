package im.moonchat.biz.controller.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountResponses;
import im.moonchat.biz.service.account.AccountService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** #4 我的账号 + 我名下的 agent（切账号入口的数据源）。 */
@RestController
@RequestMapping("/api/accounts")
@RequiredArgsConstructor
public class AccountController {

    private final AccountService accountService;

    @GetMapping("/mine")
    public AccountResponses.MineResponse mine(CurrentAccount me) {
        return accountService.mine(me);
    }
}
