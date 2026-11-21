// 入站消息：从 OneBot 事件解析成实体，队列有上限，丢了多少要如实记着。
import { conversationKey } from './conversation.js'

export const QUEUE_LIMIT = 50
const TEXT_LIMIT = 2_000

/**
 * 一条 OneBot 12 消息事件 → { conversation, message } | null。
 * 群聊被关掉时直接返回 null（连唤醒都不该发生），空文本也丢。
 */
export function parseInbound(event, { groupsEnabled = true } = {}) {
    if (!event || event.type !== 'message') return null
    const group = event.detail_type === 'group'
    if (group && !groupsEnabled) return null
    const kind = group ? 'group' : 'private'
    const id = String((group ? event.group_id : event.user_id) ?? '')
    const userId = String(event.user_id ?? '')
    if (!id || !userId) return null
    const text = (event.message ?? [])
        .filter((segment) => segment?.type === 'text')
        .map((segment) => String(segment.data?.text ?? ''))
        .join('')
    if (!text.trim()) return null
    return {
        conversation: conversationKey(kind, id),
        message: {
            messageId: String(event.message_id ?? ''),
            userId,
            text: text.slice(0, TEXT_LIMIT),
            at: Number(event.time ?? 0),
        },
    }
}

/** 队列丢掉的条数要写进工具结果，别让 agent 以为拿到的就是全部。 */
export function lossNote(count) {
    return count > 0 ? `（另有 ${count} 条更早的消息因积压被丢弃）` : ''
}

/** `[时间] 名字(id): 正文` 一行一条。 */
export function formatMessages(messages, nameOf) {
    return messages.map((item) => {
        const at = item.at ? new Date(item.at * 1000).toISOString() : ''
        const name = nameOf(item.userId)
        const who = name ? `${name}(${item.userId})` : item.userId
        return `[${at}] ${who}: ${item.text}`
    })
}
