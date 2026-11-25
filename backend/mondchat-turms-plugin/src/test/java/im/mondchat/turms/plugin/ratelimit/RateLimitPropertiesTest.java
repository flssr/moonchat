package im.mondchat.turms.plugin.ratelimit;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class RateLimitPropertiesTest {

    @Test
    void shouldUseAccountDefaults() {
        AccountRateLimitProperties properties = new AccountRateLimitProperties();

        assertEquals(60, properties.getCapacity());
        assertEquals(60, properties.getInitialTokens());
        assertEquals(1, properties.getTokensPerPeriod());
        assertEquals(1_000, properties.getRefillIntervalMillis());
    }

    @Test
    void shouldUseConversationDefaults() {
        ConversationRateLimitProperties properties = new ConversationRateLimitProperties();

        assertEquals(20, properties.getCapacity());
        assertEquals(20, properties.getInitialTokens());
        assertEquals(1, properties.getTokensPerPeriod());
        assertEquals(3_000, properties.getRefillIntervalMillis());
    }
}
