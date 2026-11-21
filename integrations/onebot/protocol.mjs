// 纯协议层：不 import 任何依赖，selftest 可以直接跑。
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
 * 按 UTF-16 码元切段：Biz 的 `@Size(max = 500)` 数的是 Java 的 `String.length()`，
 * 一个 emoji 算 2。这里按同样的口径切，只是在码元边界上避开代理对，别切出半个字符。
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
