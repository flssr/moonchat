package im.moonchat.biz.account;

import im.moonchat.biz.auth.CurrentAccount;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** #1 注册、#2 登录、#20 续期：两个不认证的入口 + 一个只认登录 JWT 的入口。 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AccountService accounts;

    AuthController(AccountService accounts) {
        this.accounts = accounts;
    }

    /** 注册不签发 JWT：注册与登录是两次独立请求。 */
    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public AccountDtos.RegisterResponse register(@Valid @RequestBody AccountDtos.RegisterRequest request) {
        return accounts.register(request);
    }

    @PostMapping("/login")
    public AccountDtos.TokenResponse login(@Valid @RequestBody AccountDtos.LoginRequest request) {
        return accounts.login(request);
    }

    @PostMapping("/refresh")
    public AccountDtos.TokenResponse refresh(CurrentAccount me) {
        return accounts.refresh(me);
    }
}
