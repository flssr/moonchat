package im.moonchat.biz.auth;

import java.util.List;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** 只做一件事：让 {@link CurrentAccount} 能出现在控制器参数上。 */
@Configuration
public class AuthWebConfig implements WebMvcConfigurer {

    private final CurrentAccountArgumentResolver currentAccount;

    AuthWebConfig(CurrentAccountArgumentResolver currentAccount) {
        this.currentAccount = currentAccount;
    }

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        resolvers.add(currentAccount);
    }
}
