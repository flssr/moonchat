package im.mondchat.biz.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * `mondchat.turms.http.*`：Biz 打 Turms Admin REST 的超时。
 *
 * <p>不配超时的后果不是「慢」，是「一起死」：Turms 只卡不回（不是连不上）时，每个请求会一直占着
 * Tomcat 线程，200 个线程用完连健康检查都过不去；投影派发器也会挂在那一条事件上，`domain_event`
 * 积压只增不减。有超时之后这类失败会退回正常路径（写路径回 503、派发器记 `last_error` 并退避）。
 */
@ConfigurationProperties("mondchat.turms.http")
public record TurmsAdminHttpProperties(
        /** 建立连接的上限：连不上是明确的故障，很快就能判出来。 */
        @DefaultValue("2s") Duration connectTimeout,
        /** 等服务端回包的上限：要覆盖 Admin 端最慢的一次分页查询。 */
        @DefaultValue("5s") Duration readTimeout) {
}
