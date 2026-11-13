package im.moonchat.biz.controller.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;
import im.moonchat.biz.service.account.AccountService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** #4 我的账号 + 我名下的 agent（切账号入口的数据源），#6 改本账号名字，#7 资料页。 */
@RestController
@RequestMapping("/api/accounts")
@RequiredArgsConstructor
public class AccountController {

    private final AccountService accountService;

    @GetMapping("/mine")
    public AccountResponses.MineResponse mine(CurrentAccount me) {
        return accountService.mine(me);
    }

    @PatchMapping("/me")
    public AccountResponses.RenameResponse rename(CurrentAccount me,
            @Valid @RequestBody AccountRequests.DisplayNameRequest request) {
        return accountService.rename(me, request);
    }

    @GetMapping("/{accountId}")
    public AccountResponses.ProfileResponse profile(CurrentAccount me,
            @PathVariable("accountId") long accountId) {
        return accountService.profile(me, accountId);
    }
}
