package im.mondchat.biz.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 本地调试用的 CORS：Flutter Web 开发服务器（`flutter run -d web-server`）与 API 不同源，
 * 浏览器会拦掉所有 `/api` 请求。只在 `dev` profile 生效，白名单固定为本机来源，不放开上线环境。
 *
 * <p>生产是 nginx 同源反代，不需要也不应该加这段。凭据走 `Authorization` 头、不用 cookie，
 * 所以不开启 `allowCredentials`。
 */
@Configuration
@Profile("dev")
public class DevCorsConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns("http://localhost:*", "http://127.0.0.1:*")
                .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
                .allowedHeaders("Authorization", "Content-Type", "X-Device-Type")
                .maxAge(3600);
    }
}
