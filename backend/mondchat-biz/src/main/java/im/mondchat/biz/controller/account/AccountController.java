package im.mondchat.biz.controller.account;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.account.AccountRequests;
import im.mondchat.biz.dto.account.AccountResponses;
import im.mondchat.biz.service.account.AccountService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
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

    @GetMapping("/me")
    public AccountResponses.AccountProfileResponse myProfile(CurrentAccount me) {
        return accountService.myProfile(me);
    }

    /** `PUT` 是全量提交语义：三个字段都必传（契约 §4.3），不是部分更新。 */
    @PutMapping("/me")
    public AccountResponses.AccountProfileResponse updateProfile(CurrentAccount me,
            @Valid @RequestBody AccountRequests.UpdateProfileRequest request) {
        return accountService.updateProfile(me, request);
    }

    @GetMapping("/{accountId}")
    public AccountResponses.ProfileResponse profile(CurrentAccount me,
            @PathVariable("accountId") long accountId) {
        return accountService.profile(me, accountId);
    }
}
