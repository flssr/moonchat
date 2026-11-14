package im.mondchat.biz.dto.message;

import java.time.Instant;

/**
 * #19 的响应体。`message_id` 由写入网关生成后随代发提交给 Turms（Admin `CreateMessageDTO.id`）——
 * Admin `POST /messages` 返回空 body，不回传 id（docs/truth/backend/messaging.md）。
 * `sent_at` 是网关交出这一刻的时间，Turms 的 `deliveryDate` 与之差毫秒级；翻历史仍用 `deliveryDate` 做游标。
 */
public final class MessageResponses {

    private MessageResponses() {
    }

    public record Conversation(String type, long id) {
    }

    public record SendResponse(long messageId, Conversation conversation, Instant sentAt) {
    }
}
