// 后台记忆任务用的最小模型调用：不进 DSH 会话，不碰人格，只问一次宿主 llm。
import { randomUUID } from 'node:crypto'

function defaultModel(ctx, config) {
    if (config?.model?.provider && config?.model?.model) {
        return { provider: config.model.provider, model: config.model.model }
    }
    try {
        const service = ctx?.get?.('agentDefaultModel')
        const selection = typeof service?.currentSelection === 'function' ? service.currentSelection() : null
        if (selection?.provider && selection?.model) {
            return { provider: selection.provider, model: selection.model }
        }
    } catch {
        // 老宿主没有这个服务：按拿不到模型处理。
    }
    return null
}

export async function askHostModel(ctx, { system, text, maxTokens = 800, temperature = 0.2, config } = {}) {
    const llm = ctx?.llm ?? ctx?.get?.('llm')
    if (!llm || typeof llm.stream !== 'function') throw new Error('宿主没有 llm 服务')
    const target = defaultModel(ctx, config)
    if (!target) throw new Error('拿不到默认模型')
    const params = {
        provider: target.provider,
        model: target.model,
        system: String(system ?? ''),
        messages: [{
            role: 'user',
            id: randomUUID(),
            content: [{ type: 'text', text: String(text ?? '') }],
            source: { kind: 'plugin', plugin: 'jadekaninchen' },
        }],
        maxTokens,
        temperature,
    }
    let output = ''
    for await (const chunk of llm.stream(params)) {
        if (!chunk) continue
        if (chunk.type === 'text-delta') output += chunk.text
        if (chunk.type === 'finish' && chunk.reason?.kind === 'error') {
            const failure = chunk.reason.failure ?? {}
            throw new Error(`记忆模型报错：${failure.message ?? failure.code ?? '未知'}`)
        }
    }
    return output.trim()
}
