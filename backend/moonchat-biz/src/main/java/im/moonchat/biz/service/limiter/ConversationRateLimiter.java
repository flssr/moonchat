package im.moonchat.biz.service.limiter;

import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.config.LimitProperties;
import java.time.Duration;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/**
 * 会话级限流桶：两级桶里的第二级，比账号级更小，只对 `agent` 来源的发言生效。
 * 键按 `(账号, 会话)` 落，重启归零——限流是可重建的运行状态，不是业务真相。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ConversationRateLimiter {

    private static final String KEY_PREFIX = "moonchat:ratelimit:conversation:";
    private static final Duration WINDOW = Duration.ofMinutes(1);

    private final StringRedisTemplate redis;
    private final LimitProperties properties;

    public void check(long accountId, String conversationType, long conversationId) {
        String key = KEY_PREFIX + accountId + ":" + conversationType + ":" + conversationId;
        Long hits = redis.opsForValue().increment(key);
        if (hits != null && hits == 1L) {
            redis.expire(key, WINDOW);
        }
        if (hits != null && hits > properties.conversationPerMinute()) {
            // 命中只打日志：V1 不建审计表（docs/goal-and-requirements.md §5.3）
            log.warn("限流命中：accountId={} 会话级桶 {}:{} {} 次/分钟", accountId, conversationType,
                    conversationId, properties.conversationPerMinute());
            throw ApiException.rateLimited();
        }
    }
}
