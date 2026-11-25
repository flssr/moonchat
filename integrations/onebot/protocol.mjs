// 纯桥逻辑：协议形状与直发辅助，不 import 任何依赖，selftest 可以直接跑。
import { randomUUID } from 'node:crypto'

export const PLATFORM = 'mondchat'
export const TEXT_LIMIT = 500

/** 网关地址可能是 http(s)://、ws(s):// 或裸 host:port，统一成 ws(s)://。 */
export function toWsUrl(gatewayUrl) {
    const url = String(gatewayUrl ?? '').trim()
    if (url.startsWith('ws://') || url.startsWith('wss://')) return url
    if (url.startsWith('https://')) return `wss://${url.slice('https://'.length)}`
    if (url.startsWith('http://')) return `ws://${url.slice('http://'.length)}`
    return `ws://${url}`
}

/**
 * 500 是 Turms `max-text-limit` 的默认值。按 UTF-16 码元切，与 Java 的
 * `String.length()` 同口径（一个 emoji 算 2），并在边界避开代理对。
 */
export function splitText(text, limit = TEXT_LIMIT) {
    const source = String(text ?? '')
    const parts = []
    let start = 0
    while (start < source.length) {
        let end = Math.min(start + limit, source.length)
        // end 落在低位代理上说明要劈开一对：退一格，让这对留在同一段。
        if (end < source.length && isLowSurrogate(source.charCodeAt(end))) end -= 1
        const part = source.slice(start, end)
        if (part.trim()) parts.push(part)
        start = end
    }
    return parts
}

function isLowSurrogate(code) {
    return code >= 0xdc00 && code <= 0xdfff
}

/** 群列表整体替换，避免已退群或已删除的旧映射一直留着。 */
export function buildRoomMaps(rooms) {
    const roomIdByTurmsGroupId = new Map()
    const turmsGroupIdByRoomId = new Map()
    const roomTitleById = new Map()
    for (const room of rooms) {
        if (room.turms_group_id == null) continue
        const turmsGroupId = String(room.turms_group_id)
        const roomId = String(room.room_id)
        roomIdByTurmsGroupId.set(turmsGroupId, roomId)
        turmsGroupIdByRoomId.set(roomId, turmsGroupId)
        roomTitleById.set(roomId, String(room.name ?? ''))
    }
    return { roomIdByTurmsGroupId, turmsGroupIdByRoomId, roomTitleById }
}

export function removeRoom(roomMaps, roomId) {
    const id = String(roomId)
    const turmsGroupId = roomMaps.turmsGroupIdByRoomId.get(id)
    roomMaps.turmsGroupIdByRoomId.delete(id)
    roomMaps.roomTitleById.delete(id)
    if (turmsGroupId !== undefined) roomMaps.roomIdByTurmsGroupId.delete(turmsGroupId)
}

/** 只经当前账号已登录的 Turms 连接发送；返回 OneBot 12 的字符串 id 与秒级时间。 */
export async function sendText(messageService, { isGroupMessage, targetId, text }) {
    let last = null
    for (const chunk of splitText(text)) {
        last = await messageService.sendMessage({
            isGroupMessage,
            targetId: String(targetId),
            text: chunk,
        })
    }
    return {
        message_id: String(last.data),
        time: last.timestamp.getTime() / 1000,
    }
}

/** Turms ResponseError 的 code/reason 原样落到 OneBot 的 retcode/message。 */
export function failureView(error) {
    const retcode = error?.retcode ?? error?.code ?? 1500
    const message = error?.retcode !== undefined
        ? error.message
        : error?.reason ?? error?.message ?? String(error)
    return { retcode, message: String(message) }
}

/**
 * OneBot 消息段 → 纯文本。平台没有图片/文件/语音，遇到非 text 段要显式报错，
 * 不能悄悄丢——应用会以为发出去了。
 */
export function segmentsToText(message) {
    if (typeof message === 'string') return { text: message, unsupported: null }
    const segments = Array.isArray(message) ? message : []
    const texts = []
    for (const segment of segments) {
        if (segment?.type !== 'text') {
            return { text: '', unsupported: String(segment?.type ?? 'unknown') }
        }
        texts.push(String(segment.data?.text ?? ''))
    }
    return { text: texts.join(''), unsupported: null }
}

export function buildEvent({ selfId, message, roomId }) {
    const text = String(message.text ?? '')
    const sentAt = Date.parse(String(message.deliveryDate ?? ''))
    const event = {
        id: randomUUID(),
        self: { platform: PLATFORM, user_id: String(selfId) },
        time: (Number.isFinite(sentAt) ? sentAt : Date.now()) / 1000,
        type: 'message',
        detail_type: roomId == null ? 'private' : 'group',
        sub_type: '',
        message_id: String(message.id ?? ''),
        message: [{ type: 'text', data: { text } }],
        alt_message: text,
        user_id: String(message.senderId ?? ''),
    }
    // 群消息的 group_id 用业务 room_id，不用 Turms 的 group id（两者只有桥自己知道映射）。
    if (roomId != null) event.group_id = String(roomId)
    return event
}

export function metaConnectEvent({ selfId, impl, version }) {
    return {
        id: randomUUID(),
        self: { platform: PLATFORM, user_id: String(selfId ?? '') },
        time: Date.now() / 1000,
        type: 'meta',
        detail_type: 'connect',
        sub_type: '',
        version: { impl, version, onebot_version: '12' },
    }
}

export function metaHeartbeatEvent({ selfId, intervalMs }) {
    return {
        id: randomUUID(),
        self: { platform: PLATFORM, user_id: String(selfId ?? '') },
        time: Date.now() / 1000,
        type: 'meta',
        detail_type: 'heartbeat',
        sub_type: '',
        interval: intervalMs,
    }
}

/** 桥只绑回环，但一旦被转发出去，access_token 就是唯一一道门。 */
export function isAuthorized(request, token) {
    if (!token) return true
    const url = new URL(String(request?.url ?? '/'), `http://${request?.headers?.host ?? 'localhost'}`)
    if (url.searchParams.get('access_token') === token) return true
    return request?.headers?.authorization === `Bearer ${token}`
}
