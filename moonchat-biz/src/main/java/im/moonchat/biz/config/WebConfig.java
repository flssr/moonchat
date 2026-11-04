package im.moonchat.biz.config;

import im.moonchat.biz.auth.CurrentAccountArgumentResolver;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** MVC 装配：只做一件事，让 {@code CurrentAccount} 能出现在控制器参数上。 */
@Configuration
@RequiredArgsConstructor
public class WebConfig implements WebMvcConfigurer {

    private final CurrentAccountArgumentResolver currentAccount;

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        resolvers.add(currentAccount);
    }
}
