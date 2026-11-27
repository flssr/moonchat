// mondchat_send：在当前会话里发言。切段、限流与落库都在桥和 Biz，这里只做校验与转发。
import { textBlock, oneBotText } from './present.js'

export const NAME = 'mondchat_send'

export function createSendTool(key, service) {
    return {
        name: NAME,
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
