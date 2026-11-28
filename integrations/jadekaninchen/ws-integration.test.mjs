// 端到端联调：真实 mock-onebot WebSocket + Jadekaninchen 的 bridge 客户端/服务/记忆/人格路由。
// 不连 DSH，也不连真 IM；用假宿主提供会话、工具和一次假模型调用。
// 跑法：node ws-integration.test.mjs
import assert from 'node:assert/strict'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { createMockServer } from './mock-onebot.mjs'
import { createRuntime } from './index.js'

const LLM_OUTPUT = JSON.stringify({
    summary: '刚才在聊咖啡',
    facts: [{
        text: '测试用户喜欢喝咖啡',
        subject: '100000004',
        subjectName: '测试用户',
        importance: 0.9,
    }],
})

function makeHost() {
    const state = {
        prompts: [],
        routes: new Map(),
        tools: new Map(),
        live: new Set(),
        sent: [],
    }
    const tools = {
        register(def) {
            state.tools.set(def.name, def)
            return () => state.tools.delete(def.name)
        },
    }
    const sessionController = {
        async create() {
            const sessionId = `ws-session-${state.live.size + 1}`
            state.live.add(sessionId)
            return { sessionId }
        },
        async resolveAgent(id) {
            return { agent: { id, ctx: { tools } } }
        },
        async prompt(request) {
            state.prompts.push(request)
            return { accepted: true }
        },
        async rename() {},
        async selectModel() {},
    }
    const ctx = {
        on: () => () => {},
        get: (key) => {
            if (key === 'connection') {
                return {
                    fetch: {
                        register(route) {
                            state.routes.set(route.path, route)
                            return () => state.routes.delete(route.path)
                        },
                    },
                }
            }
            if (key === 'permissionPresets') {
                return { catalog: () => ({ options: [] }), resolve: () => null, set: () => {} }
            }
            if (key === 'configEditor') {
                return {
                    entries: () => [{ id: 'jadekaninchen', name: 'jadekaninchen' }],
                    async edit(entry, change) {
                        state.sent.push({ entry: entry.id, config: change({}, {}) })
                    },
                }
            }
            if (key === 'agentDefaultModel') {
                return { currentSelection: () => ({ provider: 'test', model: 'test' }) }
            }
            return undefined
        },
        effect: (fn) => {
            const disposer = fn()
            state.disposers = [...(state.disposers || []), disposer]
            return disposer
        },
        provide: () => {},
        tools: { register: () => { throw new Error('不能注册全局工具') } },
        sessions: { get: (id) => (state.live.has(id) ? { id } : undefined) },
        sessionController,
        llm: {
            async *stream() {
                yield { type: 'text-delta', text: LLM_OUTPUT }
                yield { type: 'finish', reason: { kind: 'stop' } }
            },
        },
    }
    return { ctx, state }
}

async function waitFor(check, label, timeoutMs = 5_000) {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
        if (check()) return
        await new Promise((resolve) => setTimeout(resolve, 25))
    }
    throw new Error(`等待超时：${label}`)
}

const home = mkdtempSync(join(tmpdir(), 'jadekaninchen-ws-'))
const mock = await createMockServer({ port: 0, log: () => {} })
const host = makeHost()
const rt = createRuntime(host.ctx, {
    home,
    bridge: `ws://127.0.0.1:${mock.port}`,
    wakeDebounceMs: 0,
    memory: { auto: false, compressMessages: 2, tailMessages: 2 },
    persona: 'jadekaninchen',
})
rt.start()

try {
    await waitFor(() => mock.clientCount() === 1, '插件连上 mock 桥')
    await waitFor(() => rt.status().bridge.connection === 'connected', '桥连接状态')
    assert.equal(rt.status().config.persona, 'jadekaninchen')
    assert.ok(rt.status().personas.some((item) => item.id === 'jadekaninchen'))

    const key = 'private:100000004'
    for (const [id, text] of [['m1', '第一句'], ['m2', '第二句'], ['m3', '第三句'], ['m4', '第四句']]) {
        mock.emitMessage({ text, messageId: id, userId: '100000004' })
    }
    await waitFor(() => rt.service.memory.recent(key).length === 4, '四条原话进记忆')
    await waitFor(() => host.state.prompts.length > 0, '消息触发唤醒')
    const firstPrompt = host.state.prompts.at(-1).content[0].text
    assert.match(firstPrompt, /^<persona>/)
    assert.match(firstPrompt, /<context>/)

    const compressed = await rt.service.compressNow(key)
    assert.equal(compressed.summary, '刚才在聊咖啡')
    assert.equal(rt.service.memorySummary(key), '刚才在聊咖啡')
    assert.equal(rt.service.recallFacts(key, { query: '咖啡' })[0].text, '测试用户喜欢喝咖啡')

    mock.emitMessage({ text: '再聊一句', messageId: 'm5', userId: '100000004' })
    await waitFor(() => host.state.prompts.length > 1, '压缩后再唤醒')
    const memoryPrompt = host.state.prompts.at(-1).content[0].text
    assert.match(memoryPrompt, /<memory>/)
    assert.match(memoryPrompt, /刚才在聊咖啡/)

    const recall = host.state.tools.get('mondchat_recall')
    assert.ok(recall)
    const recallText = await recall.execute({ query: '咖啡' })
    assert.match(recallText, /【短期】刚才在聊咖啡/)
    assert.match(recallText, /【长期】测试用户喜欢喝咖啡/)

    const sent = await rt.service.send(key, [{ type: 'text', data: { text: '收到' } }])
    assert.equal(typeof sent.message_id, 'string')
    assert.equal(rt.service.memory.recent(key).at(-1).text, '收到')

    const personaRoute = host.state.routes.get('/api/mondchat/personas')
    const read = await (await personaRoute.fetch({
        json: async () => ({ action: 'read', id: 'jadekaninchen' }),
    })).json()
    assert.match(read.persona.body, /Jadekaninchen/)
    const saved = await (await personaRoute.fetch({
        json: async () => ({
            action: 'save',
            id: 'ws-persona',
            name: '联调人格',
            description: 'WS 联调',
            tags: ['ws'],
            body: '## 身份\n联调',
        }),
    })).json()
    assert.equal(saved.persona.id, 'ws-persona')
    const removed = await (await personaRoute.fetch({
        json: async () => ({ action: 'delete', id: 'ws-persona' }),
    })).json()
    assert.ok(!removed.personas.some((item) => item.id === 'ws-persona'))

    console.log('[jadekaninchen] ws-integration ok')
} finally {
    rt.service.dispose()
    await mock.close()
}
