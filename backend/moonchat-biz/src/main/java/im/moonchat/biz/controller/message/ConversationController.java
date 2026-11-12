package im.moonchat.biz.controller.message;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.dto.message.MessageRequests;
import im.moonchat.biz.dto.message.MessageResponses;
import im.moonchat.biz.service.message.MessageService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * #19 发言：唯一的写入口。客户端的 Turms 会话只授查询，发不出消息，所以真人客户端与 agent 端点
 * 都打这里（docs/api-contracts.md §7）。
 */
@RestController
@RequestMapping("/api/conversations")
@RequiredArgsConstructor
public class ConversationController {

    /** 客户端声明的设备类型，映射到 Turms 的 `DeviceType` 枚举名；缺省按桌面端算。 */
    private static final Map<String, String> DEVICE_TYPES = Map.of(
            "desktop", "DESKTOP",
            "browser", "BROWSER",
            "ios", "IOS",
            "android", "ANDROID",
            "others", "OTHERS");
    private static final String DEFAULT_DEVICE_TYPE = "DESKTOP";

    private final MessageService messageService;

    @PostMapping("/{type}/{id}/messages")
    @ResponseStatus(HttpStatus.CREATED)
    public MessageResponses.SendResponse send(CurrentAccount me,
            @PathVariable("type") String conversationType,
            @PathVariable("id") long conversationId,
            @RequestHeader(name = "X-Device-Type", required = false) String deviceType,
            @Valid @RequestBody MessageRequests.SendRequest request,
            HttpServletRequest httpRequest) {
        return messageService.send(me, conversationType, conversationId, request, deviceType(deviceType),
                clientIp(httpRequest));
    }

    /** 入口只校验一次：枚举外取值就是 `validation_failed`，之后靠类型（一个枚举名）流转。 */
    private static String deviceType(String declared) {
        if (declared == null || declared.isBlank()) {
            return DEFAULT_DEVICE_TYPE;
        }
        String mapped = DEVICE_TYPES.get(declared.trim().toLowerCase());
        if (mapped == null) {
            throw ApiException.validationFailed("X-Device-Type", "X-Device-Type 只能是 " + DEVICE_TYPES.keySet());
        }
        return mapped;
    }

    /** 只在反代后面才有意义的值，不参与任何判定，只随代发交给 Turms。 */
    private static String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
