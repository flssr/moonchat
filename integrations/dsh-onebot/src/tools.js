// 会话内的两个工具。工具只做参数校验与呈现，真正的用例在 service 上。
import { formatMessages, lossNote } from './model/message.js'

const textBlock = (text) => [{ type: 'text', text: String(text) }]
// OneBot 的消息段是 {type, data}，DSH 的 ContentBlock 是 {type, text}，别混用。
const oneBotText = (text) => [{ type: 'text', data: { text: String(text) } }]

export const TOOL_UNREAD = 'mondchat_unread'
export const TOOL_SEND = 'mondchat_send'

/** 把两个工具挂到某个 agent 的上下文里；返回 disposer 列表。 */
export function registerTools(agent, key, service) {
    const tools = agent?.ctx?.tools
    if (typeof tools?.register !== 'function') return []
    return [tools.register(unreadTool(key, service)), tools.register(sendTool(key, service))]
}

function unreadTool(key, service) {
    return {
        name: TOOL_UNREAD,
        description: `读取 ${service.labelFor(key)} 里还没处理的消息。读走就清空，不重复出现。`,
        parameters: { type: 'object', properties: {}, additionalProperties: false },
        output: { schema: { type: 'string' }, render: (_args, value) => textBlock(value) },
        async execute() {
            const taken = service.takeMessages(key)
            if (taken.messages.length === 0) return lossNote(taken.dropped) || '没有未读消息。'
            const senders = [...new Set(taken.messages.map((item) => item.userId))]
            const names = new Map(
                await Promise.all(senders.map(async (id) => [id, await service.displayName('user', id)])),
            )
            const lines = formatMessages(taken.messages, (id) => names.get(id))
            return [lossNote(taken.dropped), ...lines].filter(Boolean).join('\n')
        },
    }
}

function sendTool(key, service) {
    return {
        name: TOOL_SEND,
        description: `在 ${service.labelFor(key)} 里发一条消息。不超过 500 字，超出会自动切段。`,
        parameters: {
            type: 'object',
            properties: { text: { type: 'string', description: '要发的内容' } },
            required: ['text'],
            additionalProperties: false,
        },
        output: {
            schema: { type: 'object', properties: { message_id: { type: 'string' } } },
            render: (_args, value) => textBlock(`已发送（message_id=${value?.message_id ?? ''}）`),
        },
        async execute(args) {
            const text = String(args?.text ?? '').trim()
            if (!text) throw new Error('text 不能为空')
            return service.send(key, oneBotText(text))
        },
    }
}
