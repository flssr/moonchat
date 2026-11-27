// mondchat_recall：读这个会话的本地长期记忆。队列取走的消息仍在这里，可按关键词检索。
import { textBlock } from './present.js'

export const NAME = 'mondchat_recall'

export function createRecallTool(key, service) {
    return {
        name: NAME,
        description: `读取 ${service.labelFor(key)} 保存在本机的长期记忆；消息被 unread 取走或插件重启后仍保留。`,
        parameters: {
            type: 'object',
            properties: {
                query: { type: 'string', description: '可选关键词，大小写不敏感；不传就取最近的记忆' },
                limit: { type: 'integer', minimum: 1, maximum: 50, description: '最多返回多少条，默认 20' },
            },
            additionalProperties: false,
        },
        output: { schema: { type: 'string' }, render: (_args, value) => textBlock(value) },
        async execute(args) {
            const query = String(args?.query ?? '').trim()
            const limit = Number(args?.limit ?? 20)
            const records = service.recall(key, { query, limit })
            if (records.length === 0) {
                return query ? '没有找到匹配的记忆。' : '这个会话还没有长期记忆。'
            }
            const senders = [...new Set(records
                .filter((record) => record.direction === 'in' && record.userId)
                .map((record) => record.userId))]
            const names = new Map(
                await Promise.all(senders.map(async (id) => [id, await service.displayName('user', id)])),
            )
            return records.map((record) => {
                const at = new Date(record.at).toISOString()
                const name = names.get(record.userId)
                const who = record.direction === 'out'
                    ? '我'
                    : name ? `${name}(${record.userId})` : record.userId || '对方'
                return `[${at}] ${who}: ${record.text}`
            }).join('\n')
        },
    }
}
