package im.mondchat.turms.plugin.ratelimit;

import java.util.Iterator;
import java.util.concurrent.ConcurrentHashMap;
import reactor.core.publisher.Mono;
import im.turms.server.common.access.client.dto.request.TurmsRequest;
import im.turms.server.common.access.client.dto.request.message.CreateMessageRequest;
import im.turms.server.common.access.common.ResponseStatusCode;
import im.turms.server.common.infra.plugin.TurmsExtension;
import im.turms.server.common.infra.throttle.TokenBucket;
import im.turms.server.common.infra.throttle.TokenBucketContext;
import im.turms.service.access.servicerequest.dto.ClientRequest;
import im.turms.service.access.servicerequest.dto.RequestHandlerResult;
import im.turms.service.infra.plugin.extension.ClientRequestHandler;

/**
 * 统一发送限流（不分来源）：在默认处理之前拦 `CREATE_MESSAGE_REQUEST`，命中回
 * `CLIENT_REQUESTS_TOO_FREQUENT`（1101，429 语义）。两级桶都是**进程内**的
 * {@link TokenBucket}：单实例与今天的 Redis 桶等价，扩到 N 个实例就是 N 倍额度（已知上限，
 * 升级路径是改读宿主 Redis 的共享计数）。
 *
 * <p>拒绝时返回带 {reason} 的结果即可短路后续 handler；放行返回 `Mono.empty()`。
 */
public class RateLimitExtension extends TurmsExtension implements ClientRequestHandler {

    /** 桶空闲多久后回收；与 Tokens 已回满的桶一起清，避免字典随账号/会话数无限增长。 */
    private static final long IDLE_ENTRY_TTL_NANOS = 10L * 60 * 1_000_000_000L;
    private static final long CLEANUP_INTERVAL_MILLIS = 60_000L;

    private final ConcurrentHashMap<Long, TokenBucket> accountBuckets = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, TokenBucket> conversationBuckets = new ConcurrentHashMap<>();

    private TokenBucketContext accountContext;
    private TokenBucketContext conversationContext;
    private volatile Thread cleaner;

    @Override
    protected Mono<Void> start() {
        accountContext = new TokenBucketContext(loadProperties(AccountRateLimitProperties.class));
        conversationContext = new TokenBucketContext(loadProperties(ConversationRateLimitProperties.class));
        Thread thread = new Thread(this::cleanupLoop, "mondchat-rate-limit-cleaner");
        thread.setDaemon(true);
        thread.start();
        cleaner = thread;
        return Mono.empty();
    }

    @Override
    protected Mono<Void> stop() {
        Thread thread = cleaner;
        if (thread != null) {
            thread.interrupt();
        }
        accountBuckets.clear();
        conversationBuckets.clear();
        return Mono.empty();
    }

    @Override
    public Mono<RequestHandlerResult> handle(ClientRequest clientRequest) {
        TurmsRequest request = clientRequest.turmsRequest();
        if (request == null || request.getKindCase() != TurmsRequest.KindCase.CREATE_MESSAGE_REQUEST) {
            return Mono.empty();
        }
        long userId = clientRequest.userId();
        long now = System.nanoTime();
        TokenBucket accountBucket = accountBuckets.computeIfAbsent(userId, id -> new TokenBucket(accountContext));
        if (!accountBucket.tryAcquire(now)) {
            return Mono.just(RequestHandlerResult.of(ResponseStatusCode.CLIENT_REQUESTS_TOO_FREQUENT,
                    "发送过于频繁：账号级上限"));
        }

        CreateMessageRequest message = request.getCreateMessageRequest();
        String conversationKey = userId + (message.hasGroupId()
                ? ":g" + message.getGroupId()
                : ":u" + message.getRecipientId());
        TokenBucket conversationBucket = conversationBuckets.computeIfAbsent(conversationKey,
                key -> new TokenBucket(conversationContext));
        if (!conversationBucket.tryAcquire(now)) {
            return Mono.just(RequestHandlerResult.of(ResponseStatusCode.CLIENT_REQUESTS_TOO_FREQUENT,
                    "发送过于频繁：会话级上限"));
        }
        return Mono.empty();
    }

    private void cleanupLoop() {
        while (!Thread.currentThread().isInterrupted()) {
            try {
                Thread.sleep(CLEANUP_INTERVAL_MILLIS);
            } catch (InterruptedException e) {
                return;
            }
            try {
                removeExpired(accountBuckets);
                removeExpired(conversationBuckets);
            } catch (RuntimeException e) {
                // 清理失败不影响限流本身：下一轮再试
            }
        }
    }

    private static void removeExpired(ConcurrentHashMap<?, TokenBucket> buckets) {
        long now = System.nanoTime();
        Iterator<TokenBucket> iterator = buckets.values().iterator();
        while (iterator.hasNext()) {
            TokenBucket bucket = iterator.next();
            if (now - bucket.getLastRefillTimeNanos() > IDLE_ENTRY_TTL_NANOS
                    && bucket.isTokensMoreThanOrEqualsToInitialTokens()) {
                iterator.remove();
            }
        }
    }
}
