package im.mondchat.biz.auth;

import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.service.account.AccountKeyService;
import im.mondchat.biz.service.account.AccountService;
import im.mondchat.biz.service.auth.LoginTokenService;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

/**
 * 把 `Authorization: Bearer <token>` 解析成 {@link CurrentAccount}。一个头装两种凭据：
 * 登录 JWT（认作 `owner`）与 agent 账号密钥（认作 `agent`）。
 *
 * <p>参数写成 `Optional<CurrentAccount>` 时没有凭据不算失败——#3 的账号密钥形态就是不带认证头的
 * （docs/truth/backend/identity.md）；带了但验不过仍然回 `unauthenticated`。
 *
 * <p>不做成过滤器：解析失败要落到统一的失败体，而过滤器里的异常在 advice 之外。
 */
@Component
@RequiredArgsConstructor
public class CurrentAccountArgumentResolver implements HandlerMethodArgumentResolver {

    private static final String BEARER = "Bearer ";

    private final LoginTokenService loginTokens;
    private final AccountKeyService accountKeys;
    private final AccountService accounts;

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        if (!parameter.isOptional()) {
            return CurrentAccount.class.equals(parameter.getParameterType());
        }
        // Spring 7 的 nestedIfOptional() 对 Optional<T> 只返回自身，只能按泛型实参判
        Type generic = parameter.getNestedGenericParameterType();
        return generic instanceof ParameterizedType optional
                && CurrentAccount.class.equals(optional.getActualTypeArguments()[0]);
    }

    @Override
    public Object resolveArgument(MethodParameter parameter, ModelAndViewContainer mavContainer,
            NativeWebRequest webRequest, WebDataBinderFactory binderFactory) {
        boolean optional = parameter.isOptional();
        String header = webRequest.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.startsWith(BEARER)) {
            if (optional) {
                return Optional.empty();
            }
            throw ApiException.unauthenticated();
        }
        String token = header.substring(BEARER.length()).trim();
        // 两种凭据的形状不同：登录 JWT 是三段 base64url（带点），账号密钥是 UUID（不带点）。
        boolean loginToken = token.indexOf('.') > 0;
        long accountId = loginToken ? loginTokens.verify(token) : accountKeys.authenticate(token);
        accounts.requireExists(accountId);
        CurrentAccount account = new CurrentAccount(accountId,
                loginToken ? CurrentAccount.Source.OWNER : CurrentAccount.Source.AGENT);
        return optional ? Optional.of(account) : account;
    }
}
