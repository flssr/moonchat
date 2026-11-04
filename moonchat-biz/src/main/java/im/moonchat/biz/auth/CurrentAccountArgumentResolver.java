package im.moonchat.biz.auth;

import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.service.auth.LoginTokenService;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

/**
 * 把 `Authorization: Bearer <登录 JWT>` 解析成 {@link CurrentAccount}。
 * 不做成过滤器：解析失败要落到统一的失败体，而过滤器里的异常在 advice 之外。
 */
@Component
public class CurrentAccountArgumentResolver implements HandlerMethodArgumentResolver {

    private static final String BEARER = "Bearer ";

    private final LoginTokenService loginTokens;

    public CurrentAccountArgumentResolver(LoginTokenService loginTokens) {
        this.loginTokens = loginTokens;
    }

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return CurrentAccount.class.equals(parameter.getParameterType());
    }

    @Override
    public Object resolveArgument(MethodParameter parameter, ModelAndViewContainer mavContainer,
            NativeWebRequest webRequest, WebDataBinderFactory binderFactory) {
        String header = webRequest.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.startsWith(BEARER)) {
            throw ApiException.unauthenticated();
        }
        return new CurrentAccount(loginTokens.verify(header.substring(BEARER.length()).trim()));
    }
}
