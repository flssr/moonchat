package im.moonchat.biz.controller.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;
import im.moonchat.biz.service.account.AccountService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** #1 注册、#2 登录、#20 续期：两个不认证的入口 + 一个只认登录 JWT 的入口。 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AccountService accountService;

    /** 注册不签发 JWT：注册与登录是两次独立请求。 */
    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public AccountResponses.RegisterResponse register(
            @Valid @RequestBody AccountRequests.RegisterRequest request) {
        return accountService.register(request);
    }

    @PostMapping("/login")
    public AccountResponses.TokenResponse login(@Valid @RequestBody AccountRequests.LoginRequest request) {
        return accountService.login(request);
    }

    @PostMapping("/refresh")
    public AccountResponses.TokenResponse refresh(CurrentAccount me) {
        return accountService.refresh(me);
    }
}
