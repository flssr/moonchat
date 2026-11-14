package im.moonchat.biz.config;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.servers.Server;
import io.swagger.v3.oas.models.media.Schema;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springdoc.core.customizers.GlobalOpenApiCustomizer;
import org.springdoc.core.customizers.OperationCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * `/v3/api-docs` 的来源：路由与字段都从控制器与 DTO 扫出来，不提交静态副本。
 * 不在别处再手写一份。
 *
 * <p>认证头两种凭据（登录 JWT / 账号密钥）都走 `Authorization: Bearer`，所以只声明一个
 * `bearerAuth`；注册与登录两条路由在 {@code AuthController} 上显式豁免。
 */
@Configuration
@OpenAPIDefinition(
        info = @Info(
                title = "MoonChat Biz API",
                version = "v1",
                description = "Biz 业务接口（/api/*）。错误响应统一为 {code, message}，客户端与 agent 只按 code 分流。"),
        servers = @Server(url = "http://localhost:8080", description = "本机 biz"),
        security = @SecurityRequirement(name = "bearerAuth"))
@SecurityScheme(
        name = "bearerAuth",
        type = SecuritySchemeType.HTTP,
        scheme = "bearer",
        description = "登录 JWT（真人客户端）或账号密钥（agent 端点），两种都放在这个头里。")
public class OpenApiConfig {

    /**
     * 认证由 `CurrentAccountArgumentResolver` 从请求头解析，不是普通查询参数：
     * 扫出来的 `me` 参数要从文档里拿掉，否则 Apifox 会让人往 query 里填一个对象。
     */
    @Bean
    OperationCustomizer hideCurrentAccountParameter() {
        return (operation, handlerMethod) -> {
            if (operation.getParameters() != null) {
                operation.getParameters().removeIf(parameter -> parameter.getSchema() != null
                        && "#/components/schemas/CurrentAccount".equals(parameter.getSchema().get$ref()));
                if (operation.getParameters().isEmpty()) {
                    operation.setParameters(null);
                }
            }
            return operation;
        };
    }

    /**
     * 线上字段是 snake_case（`spring.jackson.property-naming-strategy`），但 swagger-core 生成
     * schema 时不读这个全局策略、只认 pom 里的注解，于是这里把属性名照同一条规则转一遍，
     * 免得 Apifox 里示例请求体是 `{"accountId":...}` 而服务端要 `{"account_id":...}`。
     */
    @Bean
    GlobalOpenApiCustomizer snakeCaseSchemaProperties() {
        PropertyNamingStrategies.SnakeCaseStrategy names = new PropertyNamingStrategies.SnakeCaseStrategy();
        return openApi -> {
            if (openApi.getComponents() == null || openApi.getComponents().getSchemas() == null) {
                return;
            }
            openApi.getComponents().getSchemas().values().forEach(schema -> renameProperties(schema, names));
        };
    }

    private static void renameProperties(Schema<?> schema, PropertyNamingStrategies.SnakeCaseStrategy names) {
        if (schema.getProperties() != null) {
            Map<String, Schema> renamed = new LinkedHashMap<>();
            schema.getProperties().forEach((name, property) -> renamed.put(names.translate(name), property));
            schema.setProperties(renamed);
        }
        if (schema.getRequired() != null) {
            schema.setRequired(schema.getRequired().stream().map(names::translate).toList());
        }
    }
}
