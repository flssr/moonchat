package im.moonchat.biz.service.message;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.message.MessageRequests;
import im.moonchat.biz.dto.message.MessageResponses;

/**
 * 写入网关（docs/api-contracts.md §7）：认证凭据 → 归属 → 会话解析 → 授权事实 → 限流 →
 * 来源标记写日志 → 交给 `im-facade` 代发。顺序不许调换，PG 零写入。
 */
public interface MessageService {

    /** #19 发言：唯一写入口。发送者只取自凭据，不接受请求体自报。 */
    MessageResponses.SendResponse send(CurrentAccount me, String conversationType, long conversationId,
            MessageRequests.SendRequest request, String senderDeviceType, String senderIp);
}
