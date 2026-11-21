package im.mondchat.biz.service.message;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.message.MessageRequests;
import im.mondchat.biz.dto.message.MessageResponses;

/**
 * 写入网关（docs/truth/backend/messaging.md）：认证凭据 → 归属 → 会话解析 → 授权事实 → 限流 →
 * 来源标记写日志 → 交给 `im-facade` 代发。顺序不许调换，PG 零写入。
 */
public interface MessageService {

    /** #19 发言：唯一写入口。发送者只取自凭据，不接受请求体自报。 */
    MessageResponses.SendResponse send(CurrentAccount me, String conversationType, long conversationId,
            MessageRequests.SendRequest request, String senderDeviceType, String senderIp);

    /**
     * #37 已读上报：把「本人该会话的已读时间」代写进 Turms（服务端此刻）。
     * 只动自己的读游标，不写 PG、不产生消息、不进限流桶，冻结账号也放行。
     */
    void markRead(CurrentAccount me, String conversationType, long conversationId);
}
