package im.moonchat.biz.dto.message;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** #19 的请求体：正文 500 是 Turms 的 `max-text-limit` 默认值，Biz 先拦一道。 */
public final class MessageRequests {

    private MessageRequests() {
    }

    public record SendRequest(
            @NotBlank(message = "正文不能为空")
            @Size(max = 500, message = "正文最长 500 字符")
            String text) {

        public SendRequest {
            text = text == null ? null : text.trim();
        }
    }
}
