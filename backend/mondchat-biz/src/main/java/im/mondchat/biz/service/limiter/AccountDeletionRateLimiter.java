package im.mondchat.biz.service.limiter;

import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.LimitProperties;
import java.time.Duration;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

/** 注销确认按账号限频；失败密码也计数，Redis 只保存可重建的运行状态。 */
@Slf4j
@Component
@RequiredArgsConstructor
public class AccountDeletionRateLimiter {

    private static final String KEY_PREFIX = "mondchat:ratelimit:account-deletion:";
    private static final Duration WINDOW = Duration.ofMinutes(1);
    private static final DefaultRedisScript<Long> INCR_WITH_EXPIRE = new DefaultRedisScript<>(
            "local hits = redis.call('incr', KEYS[1]); "
                    + "if hits == 1 then redis.call('expire', KEYS[1], ARGV[1]); end; "
                    + "return hits", Long.class);

    private final StringRedisTemplate redis;
    private final LimitProperties properties;

    public void check(long accountId) {
        String key = KEY_PREFIX + accountId;
        Long hits = redis.execute(INCR_WITH_EXPIRE, List.of(key), String.valueOf(WINDOW.getSeconds()));
        if (hits != null && hits > properties.accountDeletionPerMinute()) {
            log.warn("注销限流命中：accountId={} {} 次/分钟", accountId, properties.accountDeletionPerMinute());
            throw ApiException.rateLimited();
        }
    }
}
