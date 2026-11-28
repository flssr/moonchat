// mondchat_unread：把当前会话积压的消息取出来，读完即清空。
// 只是 queue 的读取端，用例与状态在 service 上。
import { formatMessages, lossNote } from '../model/message.js'
import { textBlock } from './present.js'

export const NAME = 'mondchat_unread'

export function createUnreadTool(key, service) {
    return {
        name: NAME,
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
