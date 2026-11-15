package im.mondchat.biz.service.limiter;

import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.LimitProperties;
import java.time.Duration;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/**
 * 账号级限流桶：只对 `agent` 来源生效，键在 Biz 的 Redis 里，重启归零。
 * 实现只用 Redis 的原子自增与过期（docs/truth/backend/README.md），是一分钟固定窗口。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class AccountRateLimiter {

    private static final String KEY_PREFIX = "mondchat:ratelimit:account:";
    private static final Duration WINDOW = Duration.ofMinutes(1);

    private final StringRedisTemplate redis;
    private final LimitProperties properties;

    public void check(long accountId) {
        String key = KEY_PREFIX + accountId;
        Long hits = redis.opsForValue().increment(key);
        if (hits != null && hits == 1L) {
            redis.expire(key, WINDOW);
        }
        if (hits != null && hits > properties.accountPerMinute()) {
            // 命中只打日志：V1 不建审计表（docs/truth/product.md）
            log.warn("限流命中：accountId={} 账号级桶 {} 次/分钟", accountId, properties.accountPerMinute());
            throw ApiException.rateLimited();
        }
    }
}
