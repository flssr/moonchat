// mondchat_recall：读这个会话的本地记忆。短期摘要 + 长期事实 + 原话兜底。
import { textBlock } from './present.js'

export const NAME = 'mondchat_recall'

export function createRecallTool(key, service) {
    return {
        name: NAME,
        description: `读取 ${service.labelFor(key)} 保存在本机的记忆：短期摘要、长期事实和最近原话；可按关键词检索。`,
        parameters: {
            type: 'object',
            properties: {
                query: { type: 'string', description: '可选关键词；不传就取最近的记忆' },
                limit: { type: 'integer', minimum: 1, maximum: 50, description: '最多返回多少条，默认 20' },
            },
            additionalProperties: false,
        },
        output: { schema: { type: 'string' }, render: (_args, value) => textBlock(value) },
        async execute(args) {
            const query = String(args?.query ?? '').trim()
            const limit = Number(args?.limit ?? 20)
            const summary = service.memorySummary(key)
            const facts = service.recallFacts(key, { query, limit: Math.min(limit, 6) })
            const raw = service.recall(key, { query, limit })
            if (!summary && facts.length === 0 && raw.length === 0) {
                return query ? '没有找到匹配的记忆。' : '这个会话还没有长期记忆。'
            }
            const lines = []
            if (summary) lines.push(`【短期】${summary}`)
            for (const fact of facts) lines.push(`【长期】${fact.text}`)
            if (raw.length) {
                const senders = [...new Set(raw
                    .filter((entry) => entry.direction === 'in' && entry.userId)
                    .map((entry) => entry.userId))]
                const names = new Map(
                    await Promise.all(senders.map(async (id) => [id, await service.displayName('user', id)])),
                )
                for (const entry of raw) {
                    const at = new Date(entry.at).toISOString()
                    if (entry.direction === 'out') {
                        lines.push(`[${at}] 我: ${entry.text}`)
                    } else {
                        const name = names.get(entry.userId)
                        const who = name ? `${name}(${entry.userId})` : entry.userId || '对方'
                        lines.push(`[${at}] ${who}: ${entry.text}`)
                    }
                }
            }
            return lines.join('\n')
        },
    }
}
