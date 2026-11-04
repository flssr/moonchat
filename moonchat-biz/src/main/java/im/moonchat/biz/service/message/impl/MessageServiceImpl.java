package im.moonchat.biz.service.message.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.client.turms.TurmsAdminClient;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.dto.message.MessageRequests;
import im.moonchat.biz.dto.message.MessageResponses;
import im.moonchat.biz.entity.RoomInfo;
import im.moonchat.biz.entity.RoomMember;
import im.moonchat.biz.mapper.account.AccountInfoMapper;
import im.moonchat.biz.mapper.room.RoomInfoMapper;
import im.moonchat.biz.mapper.room.RoomMemberMapper;
import im.moonchat.biz.service.friendship.FriendshipService;
import im.moonchat.biz.service.limiter.AccountRateLimiter;
import im.moonchat.biz.service.limiter.ConversationRateLimiter;
import im.moonchat.biz.service.message.MessageService;
import java.time.OffsetDateTime;
import java.util.concurrent.atomic.AtomicLong;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 写入网关。这里的每一行都在 `docs/api-contracts.md` §7 的校验顺序上：认证凭据（解析器已给出）
 * → 归属（发送者只取自凭据）→ 会话解析 → 授权事实（现查 PG）→ 限流（只有 `agent` 来源进桶）
 * → 来源标记写日志 → 交出去。**PG 零写入**：消息只在 Turms，没有副本、没有发送记录表。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MessageServiceImpl implements MessageService {

    private static final String ROOM = "room";
    private static final String DM = "dm";
    private static final String FROZEN = "frozen";

    /** 一次运行内的自增，和毫秒时间戳拼成消息 id：不缓存历史 id、不排队，所以不积压内存。 */
    private static final AtomicLong SEQUENCE = new AtomicLong();

    private final RoomInfoMapper roomInfoMapper;
    private final RoomMemberMapper roomMemberMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final FriendshipService friendshipService;
    private final AccountRateLimiter accountRateLimiter;
    private final ConversationRateLimiter conversationRateLimiter;
    private final TurmsAdminClient turmsAdmin;

    @Override
    public MessageResponses.SendResponse send(CurrentAccount me, String conversationType, long conversationId,
            MessageRequests.SendRequest request, String senderDeviceType, String senderIp) {
        // 归属：发送者就是凭据认证出的账号，请求体里没有、也不接受自报的 sender
        long senderId = me.accountId();
        if (FROZEN.equals(accountInfoMapper.selectById(senderId).getStatus())) {
            throw ApiException.accountFrozen();
        }

        // 会话解析：目标必须存在，`dm` 的对端不能是自己
        boolean groupMessage = switch (conversationType) {
            case ROOM -> true;
            case DM -> false;
            default -> throw ApiException.validationFailed("type", "type 只能是 room 或 dm");
        };
        if (groupMessage) {
            resolveRoom(conversationId);
        } else {
            resolvePeer(me, conversationId);
        }

        // 授权事实：群看 `room_member` 的有效行，私聊看 `friendship`（现查 PG，没有缓存）
        if (groupMessage) {
            requireRoomMember(conversationId, senderId);
        } else if (!friendshipService.areFriends(senderId, conversationId)) {
            throw ApiException.notFriend();
        }

        // 限流：只有 agent 来源进桶，两级逐级更小；本人的发言不进任何 agent 桶
        if (me.source() == CurrentAccount.Source.AGENT) {
            accountRateLimiter.check(senderId);
            conversationRateLimiter.check(senderId, conversationType, conversationId);
        }

        // 来源标记只进结构化日志，不作权限判定（V1 不建审计表）
        log.info("发言：accountId={} source={} conversation={}:{}", senderId, me.source(), conversationType,
                conversationId);

        long messageId = nextMessageId();
        OffsetDateTime sentAt = OffsetDateTime.now();
        turmsAdmin.sendMessage(messageId, senderId, senderDeviceType, groupMessage, conversationId, request.text(),
                senderIp);
        return new MessageResponses.SendResponse(messageId,
                new MessageResponses.Conversation(conversationType, conversationId), sentAt.toInstant());
    }

    /**
     * 消息 id 由网关生成后随代发提交：Admin `POST /messages` 返回空 body，不回传 Turms 生成的 id。
     * 毫秒时间戳放进高位，进程内自增放进低 20 位：单调递增，也不保存任何历史 id。
     */
    private static long nextMessageId() {
        return (System.currentTimeMillis() << 20) | (SEQUENCE.incrementAndGet() & 0xFFFFF);
    }

    private void resolveRoom(long roomId) {
        RoomInfo room = roomInfoMapper.selectById(roomId);
        if (room == null) {
            throw ApiException.notFound("群不存在");
        }
    }

    private void resolvePeer(CurrentAccount me, long peerAccountId) {
        if (peerAccountId == me.accountId()) {
            throw ApiException.validationFailed("id", "不能给自己发私聊");
        }
        if (accountInfoMapper.selectById(peerAccountId) == null) {
            throw ApiException.notFound("账号不存在");
        }
    }

    private void requireRoomMember(long roomId, long accountId) {
        Long valid = roomMemberMapper.selectCount(new LambdaQueryWrapper<RoomMember>()
                .eq(RoomMember::getRoomId, roomId)
                .eq(RoomMember::getAccountId, accountId)
                .isNull(RoomMember::getDeletedAt));
        if (valid == null || valid == 0) {
            throw ApiException.notRoomMember();
        }
    }
}
