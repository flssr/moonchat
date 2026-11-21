// 会话标识的值对象：`private:100000004` / `group:2`。
// 纯函数，不碰宿主，可以被 selftest 直接断言。

export const PRIVATE = 'private'
export const GROUP = 'group'

/** 组一个会话 key；kind 不合法就抛，别让脏值流进映射表。 */
export function conversationKey(kind, id) {
    if (kind !== PRIVATE && kind !== GROUP) throw new Error(`未知会话类型：${kind}`)
    const value = String(id ?? '').trim()
    if (!/^\d+$/.test(value)) throw new Error(`会话 id 必须是数字：${id}`)
    return `${kind}:${value}`
}

/** 拆会话 key；不是我们认识的形状就返回 null，调用方自己决定丢还是报错。 */
export function parseConversation(key) {
    const match = /^(private|group):(\d+)$/.exec(String(key ?? ''))
    if (!match) return null
    return { kind: match[1], id: match[2] }
}

export function isGroup(key) {
    return parseConversation(key)?.kind === GROUP
}

/** 「群「测试群聊」(2)」或「与「flssr」(100000004) 的私聊」；没名字就退回 id。 */
export function describe(key, name = '') {
    const parsed = parseConversation(key)
    if (!parsed) return String(key ?? '')
    const label = name ? `「${name}」(${parsed.id})` : parsed.id
    return parsed.kind === GROUP ? `群${label}` : `与${label}的私聊`
}

/** DSH 会话标题：侧栏里认得出是哪个 MondChat 会话。 */
export function titleOf(key, name = '') {
    const parsed = parseConversation(key)
    if (!parsed) return `MondChat · ${key}`
    const label = name ? ` ${name}` : ` ${parsed.id}`
    return parsed.kind === GROUP ? `MondChat · 群${label}` : `MondChat · 与${label} 的私聊`
}

export const QUEUE_LIMIT = 50

/**
 * 一个 MondChat 会话的全部数据：名字、DSH 会话 id、待处理队列、最近活动。
 * 只存数据；推进状态用下面的纯函数返回新对象，调用方决定何时落盘。
 */
export function createConversation(key, { name = '', sessionId = null } = {}) {
    const parsed = parseConversation(key)
    if (!parsed) throw new Error(`不是会话 key：${key}`)
    return {
        key,
        kind: parsed.kind,
        id: parsed.id,
        name,
        sessionId,
        queue: [],
        dropped: 0,
        lastActivity: 0,
    }
}

/** 收一条消息：入队并截断，返回新会话；丢弃条数累加。 */
export function recordMessage(conversation, message, now = Date.now()) {
    const queue = [...conversation.queue, message]
    const overflow = Math.max(0, queue.length - QUEUE_LIMIT)
    return {
        ...conversation,
        queue: queue.slice(overflow),
        dropped: conversation.dropped + overflow,
        lastActivity: now,
    }
}

/** 取走队列：返回新会话（队列清空、丢弃清零）和被取走的消息。 */
export function takeMessages(conversation) {
    const messages = conversation.queue
    return {
        conversation: { ...conversation, queue: [], dropped: 0 },
        messages,
        dropped: conversation.dropped,
    }
}
