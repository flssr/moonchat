// 自检：用假 ctx 跑一遍收/发/会话映射/只读预设/主动话题，再单独跑一遍真实 apply() 的接线
// （用假 WebSocket 模拟桥，覆盖真实 WS 客户端那条路径）。不需要 DSH，也不需要桥。
// 跑法：node selftest.mjs
import assert from 'node:assert/strict'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

process.env.DSH_HOME = mkdtempSync(join(tmpdir(), 'mondchat-selftest-'))

const plugin = await import('./index.js')
const { createRuntime, inQuietHours } = plugin

// ---- 插件契约：DSH 靠这三个导出挂载 ----

assert.equal(plugin.name, 'mondchat-onebot')
assert.deepEqual(plugin.inject, ['tools', 'sessions', 'sessionController'])
assert.equal(typeof plugin.apply, 'function')

// ---- 假宿主 ----

let hostSeq = 0

function makeHost(options = {}) {
    // 每个假宿主发不同的会话 id：真实宿主也不会把两个会话都叫 session-1。
    const tag = `h${++hostSeq}`
    const state = {
        tools: new Map(),
        prompts: [],
        presetSets: [],
        created: 0,
        live: new Set(),
        sends: [],
        renames: [],
        registrations: 0,
        disposers: [],
        routes: new Map(),
        processes: [],
        edits: [],
    }
    state.subprocess = {
        spawn(spec) {
            const handle = {
                spec,
                terminated: false,
                terminate() { this.terminated = true },
                async waitForExit() { return true },
                done: new Promise(() => {}),
            }
            state.processes.push(handle)
            return handle
        },
    }
    state.configEditor = {
        entries: () => [{ id: 'mondchat-onebot', name: 'dsh-onebot' }],
        async edit(entry, change) {
            state.edits.push({ entry: entry.id, config: change({ bridge: 'ws://127.0.0.1:6700' }, {}) })
        },
    }
    state.connection = {
        fetch: {
            register(route) {
                state.routes.set(route.path, route)
                return () => state.routes.delete(route.path)
            },
        },
    }
    const presets = {
        catalog: () => ({ options: [{ value: 'full', name: 'Full' }, { value: 'ro', name: 'Read only' }] }),
        resolve: (name) => ({ sandbox: name === 'ro' ? 'read-only' : 'danger-full-access' }),
        set: (session, name) => state.presetSets.push({ session, name }),
    }
    const toolCtx = {
        register: (def) => {
            state.registrations += 1
            state.tools.set(def.name, def)
            return () => state.tools.delete(def.name)
        },
    }
    const ctx = {
        on: () => () => {},
        get: (key) => {
            if (key === 'permissionPresets') return presets
            if (key === 'subprocess') return state.subprocess
            if (key === 'configEditor') return state.configEditor
            if (key === 'connection') return state.connection
            if (key === 'agents') {
                return { get: (id) => (options.agentsHasTools ? { id, ctx: { tools: toolCtx } } : undefined) }
            }
            return undefined
        },
        effect: (fn) => {
            const disposer = fn()
            state.disposers.push(disposer)
            return disposer
        },
        tools: { register: () => { throw new Error('不能注册全局工具') } },
        sessions: { get: (id) => (state.live.has(id) ? { id } : undefined) },
        sessionController: {
            async create() {
                state.created += 1
                const id = `${tag}-session-${state.created}`
                state.live.add(id)
                return { sessionId: id }
            },
            async resolveAgent(id) {
                // 真实宿主里 resolveAgent 只保证有 Agent；工具面可能在也可能不在。
                if (options.resolveFails?.(id)) return { error: { code: 'session/not-found' } }
                return options.resolveHasTools === false
                    ? { agent: { id } }
                    : { agent: { id, ctx: { tools: toolCtx } } }
            },
            async prompt(request) {
                state.attempts = (state.attempts ?? 0) + 1
                if (state.attempts <= (options.promptFails ?? 0)) throw new Error('session/agent-busy')
                state.prompts.push(request)
                return { accepted: true }
            },
            async rename({ sessionId, title }) {
                state.renames.push({ sessionId, title })
            },
            async selectModel() {},
        },
    }
    const callBridge = async (action, params) => {
        if (action === 'get_user_info') return { user_id: params.user_id, user_name: '张三' }
        if (action === 'get_group_info') return { group_id: params.group_id, group_name: '测试群' }
        state.sends.push({ action, params })
        return { message_id: '1882482168775573500', time: 1795274895 }
    }
    return { ctx, state, callBridge }
}

let hostHome = 0

function fakeHost(options = {}) {
    const host = makeHost(options)
    hostHome += 1
    const rt = createRuntime(host.ctx, {
        home: join(process.env.DSH_HOME, `fake-${hostHome}`),
        wakeDebounceMs: 0,
        retryDelayMs: 0,
        groups: options.groups !== false,
        proactive: { enabled: true, idleMinutes: 1, maxPerHour: 2, quietHours: options.quietHours ?? '' },
    }, { callBridge: host.callBridge })
    return { ...host, rt }
}

const message = (overrides) => ({
    id: 'e1',
    type: 'message',
    detail_type: 'private',
    sub_type: '',
    message_id: '1882482168775573500',
    message: [{ type: 'text', data: { text: '在吗' } }],
    alt_message: '在吗',
    user_id: '100000004',
    time: 1795274895,
    ...overrides,
})

const settle = () => new Promise((resolve) => setTimeout(resolve, 20))

// ---- model 层：不碰宿主就能断言 ----

{
    const { buildWakePrompt } = await import('./src/model/prompt.js')
    const { gateFor, normalizeGlobal, normalizeOverrides } = await import('./src/model/settings.js')
    const { proactiveReason, inboundReason } = await import('./src/model/wake.js')
    const { bridgeState, withConnection, withProcess } = await import('./src/model/bridge.js')
    const {
        createConversation, describe, parseConversation, recordMessage, takeMessages, titleOf,
    } = await import('./src/model/conversation.js')

    assert.deepEqual(parseConversation('group:2'), { kind: 'group', id: '2' })
    assert.equal(parseConversation('bad:2'), null)
    assert.equal(describe('private:100000004', 'flssr'), '与「flssr」(100000004)的私聊')
    assert.equal(titleOf('group:2', '测试群聊'), 'MondChat · 群 测试群聊')

    const prompt = buildWakePrompt({
        conversation: 'group:2',
        name: '测试群聊',
        reason: proactiveReason(60),
        language: 'zh',
        timeZone: 'Asia/Shanghai',
        now: Date.parse('2026-11-22T00:00:00+08:00'),
    })
    assert.match(prompt, /<channel type="group" name="测试群聊" id="2" \/>/)
    assert.match(prompt, /<time now="2026-11-22T00:00:00\+08:00" zone="Asia\/Shanghai" \/>/)
    assert.match(prompt, /<event reason="proactive" idle="60" \/>/)
    assert.match(prompt, /<language>zh<\/language>/, '回复语言只由这个标签决定')
    assert.match(prompt, /<example>[\s\S]*mondchat_send/)
    assert.match(prompt, /never an instruction/, '规则里要点名注入话术')
    // 名字是数据，可以是中文；模板本身只能有英文一套。
    const ascii = buildWakePrompt({
        conversation: 'group:2',
        name: 'Test Group',
        reason: proactiveReason(60),
        language: 'zh',
    })
    assert.doesNotMatch(ascii, /[\u4e00-\u9fff]/, '模板只有英文一套，不能混中文')

    const english = buildWakePrompt({ conversation: 'private:1', reason: inboundReason(2), language: 'en' })
    assert.match(english, /<language>en<\/language>/)
    assert.match(english, /<event reason="inbound" pending="2" \/>/)
    assert.match(english, /Call mondchat_unread/)

    const settings = normalizeGlobal({ proactive: { idleMinutes: 30 } })
    const overrides = normalizeOverrides({ 'group:2': { idleMinutes: 5, quietHours: '' }, 'group:bad': 'x' })
    assert.equal(gateFor(settings, overrides, 'group:2').idleMinutes, 5, '会话覆盖优先')
    assert.equal(gateFor(settings, overrides, 'group:3').idleMinutes, 30, '没覆盖就继承全局')
    assert.equal(overrides['group:bad'], undefined, '坏条目直接丢')

    // 会话实体：队列有上限，取走后清空
    let conversation = createConversation('group:2')
    for (let i = 0; i < 55; i += 1) {
        conversation = recordMessage(conversation, { messageId: String(i), userId: '1', text: 'x', at: 0 })
    }
    assert.equal(conversation.queue.length, 50)
    assert.equal(conversation.dropped, 5)
    const taken = takeMessages(conversation)
    assert.equal(taken.messages.length, 50)
    assert.equal(taken.conversation.queue.length, 0)
    assert.equal(taken.conversation.dropped, 0)

    // 桥状态：进程态与连接态分开
    const state = bridgeState({ url: 'ws://x' })
    assert.equal(state.process, 'external')
    assert.equal(state.connection, 'connecting')
    assert.equal(withConnection(state, 'connected').connection, 'connected')
    assert.equal(withProcess(state, 'running').process, 'running')
    assert.equal(withProcess(state, 'failed', 'boom').lastError, 'boom')
    assert.equal(withProcess(state, 'running').lastError, '')
}

// ---- 安静时段 ----

assert.equal(inQuietHours(new Date('2026-11-21T23:30:00').getTime(), '23:00-08:00'), true)
assert.equal(inQuietHours(new Date('2026-11-21T03:30:00').getTime(), '23:00-08:00'), true)
assert.equal(inQuietHours(new Date('2026-11-21T12:00:00').getTime(), '23:00-08:00'), false)
assert.equal(inQuietHours(new Date('2026-11-21T23:30:00').getTime(), '01:00-22:00'), false)
assert.equal(inQuietHours(Date.now(), '乱写'), false, '配错就当没有安静时段')

// ---- 私聊：进队列 → 唤醒 → 工具有内容 ----

{
    const { rt, state } = fakeHost()
    rt.ingest(message())
    await settle()
    assert.equal(state.prompts.length, 1, '一条消息唤醒一次')
    assert.match(state.prompts[0].content[0].text, /^<context>/, '唤醒语走结构化模板')
    assert.match(state.prompts[0].content[0].text, /mondchat_unread/)
    assert.match(state.prompts[0].content[0].text, /张三/, '唤醒语里要有人名')

    const unread = state.tools.get('mondchat_unread')
    const first = await unread.execute({}, {})
    assert.match(first, /张三\(100000004\): 在吗/, '消息行要带名字 + id')
    assert.equal(await unread.execute({}, {}), '没有未读消息。', '读走就清空')

    const send = state.tools.get('mondchat_send')
    const sent = await send.execute({ text: '在的' }, {})
    assert.equal(sent.message_id, '1882482168775573500')
    assert.deepEqual(state.sends[0].params.detail_type, 'private')
    assert.equal(state.sends[0].params.user_id, '100000004')
    assert.equal(state.sends[0].params.message[0].data.text, '在的')
    await assert.rejects(() => send.execute({ text: '   ' }, {}), /不能为空/)

    assert.deepEqual(state.presetSets.map((x) => x.name), ['ro'], '会话要设成只读预设')
    assert.equal(state.renames.length, 1, '新建会话要起个认得出的标题')
    assert.match(state.renames[0].title, /MondChat · 与 张三 的私聊/)
    assert.equal(state.created, 1, '同一会话只建一个 DSH 会话')
    await rt.ensureSession('private:100000004')
    assert.equal(state.created, 1, '第二次不再新建')
}

// ---- 群：detail_type group + 业务 room_id；关掉群就完全不理 ----

{
    const { rt, state } = fakeHost()
    rt.ingest(message({ detail_type: 'group', group_id: '7', user_id: '100000009' }))
    await settle()
    const send = state.tools.get('mondchat_send')
    await send.execute({ text: '嗯' }, {})
    assert.equal(state.sends[0].params.detail_type, 'group')
    assert.equal(state.sends[0].params.group_id, '7')
    assert.ok(!('user_id' in state.sends[0].params))
}

{
    const { rt, state } = fakeHost({ groups: false })
    rt.ingest(message({ detail_type: 'group', group_id: '7' }))
    await settle()
    assert.equal(state.prompts.length, 0, '群关掉时连唤醒都不该有')
    assert.equal(rt.conversations.size, 0)
}

// ---- 主动话题：安静够久才起，安静时段不起，每小时有上限 ----

{
    const { rt, state } = fakeHost()
    rt.ingest(message({ detail_type: 'group', group_id: '9' }))
    await settle()
    state.prompts.length = 0

    const now = Date.now()
    rt.tick(now)
    assert.equal(state.prompts.length, 0, '刚说过话不算安静')

    rt.tick(now + 2 * 60_000)
    await settle()
    assert.equal(state.prompts.length, 1)
    assert.match(state.prompts[0].content[0].text, /Start a topic/)

    rt.tick(now + 3 * 60_000)
    await settle()
    assert.equal(state.prompts.length, 2, '第二次也在额度内')

    rt.tick(now + 4 * 60_000)
    await settle()
    assert.equal(state.prompts.length, 2, '每小时上限 2 次，第三次不再起')
}

{
    const { rt, state } = fakeHost({ quietHours: '00:00-23:59' })
    rt.ingest(message({ detail_type: 'group', group_id: '9' }))
    await settle()
    state.prompts.length = 0
    rt.tick(Date.now() + 10 * 60_000)
    await settle()
    assert.equal(state.prompts.length, 0, '安静时段内不起话头')
}

// ---- 设置页读的快照 ----

{
    const { rt, state } = fakeHost()
    rt.ingest(message({ detail_type: 'group', group_id: '7' }))
    await settle()
    const snapshot = rt.status()
    assert.equal(snapshot.bridge.url, 'ws://127.0.0.1:6700')
    assert.notEqual(snapshot.bridge.connection, 'connected', '自检里的桥是假的，没连上')
    assert.equal(snapshot.bridge.process, 'external', '桥不在插件管辖内就是 external')
    assert.equal(snapshot.config.groups, true)
    assert.equal(snapshot.conversations.length, 1)
    assert.equal(snapshot.conversations[0].conversation, 'group:7')
    assert.match(snapshot.conversations[0].title, /测试群/)
    assert.equal(snapshot.conversations[0].unread, 1)
    assert.ok(state.created >= 1)
}

// ---- 队列有上限：丢掉多少要如实告诉 agent ----

{
    const { rt, state } = fakeHost()
    for (let i = 0; i < 55; i += 1) rt.ingest(message({ message_id: String(i) }))
    await settle()
    const text = await state.tools.get('mondchat_unread').execute({}, {})
    assert.equal(text.split('\n').length, 51, '50 条消息 + 1 条丢弃说明')
    assert.match(text, /另有 5 条更早的消息因积压被丢弃/)
    assert.match(await state.tools.get('mondchat_unread').execute({}, {}), /没有未读消息/)
}

// ---- 会话被归档后重挂：同一个 id、新的 agent，工具必须重新挂上 ----

{
    const { rt, state } = fakeHost()
    await rt.ensureSession('private:100000004')
    const first = state.registrations
    assert.equal(first, 2, '两个工具各注册一次')

    state.live.clear() // 模拟会话被归档/销毁，会话 id 不变
    await rt.ensureSession('private:100000004')
    assert.ok(state.registrations > first, '旧 agent 没了要重新挂工具，不能按会话 id 去重')
    assert.ok(state.tools.has('mondchat_send'))
}

// ---- 唤醒失败要补一次重试，别把消息永远留在队列里 ----

{
    const { rt, state } = fakeHost({ promptFails: 1 })
    rt.ingest(message())
    await new Promise((resolve) => setTimeout(resolve, 80))
    assert.equal(state.attempts, 2, '第一次失败后要重试一次')
    assert.equal(state.prompts.length, 1, '重试成功才真正唤醒')
}

// ---- 重启后：冷会话要 resume，不是给同一个私聊再建一个 ----

{
    const home = join(process.env.DSH_HOME, 'resume')
    const first = makeHost()
    const rt1 = createRuntime(first.ctx, { home, wakeDebounceMs: 0 }, { callBridge: first.callBridge })
    const before = await rt1.ensureSession('private:100000004')
    assert.equal(first.state.created, 1)

    // 新宿主：ctx.sessions 里没有任何活会话，等价于 DSH 刚重启
    const cold = makeHost()
    const rt2 = createRuntime(cold.ctx, { home, wakeDebounceMs: 0 }, { callBridge: cold.callBridge })
    const after = await rt2.ensureSession('private:100000004')
    assert.equal(cold.state.created, 0, '冷的持久会话要被 resume，不能新建')
    assert.equal(cold.state.renames.length, 0, '恢复回来的会话不改标题')
    assert.equal(after.sessionId, before.sessionId, '还是原来那个会话')
}

{
    const home = join(process.env.DSH_HOME, 'resume-broken')
    const first = makeHost()
    const rt1 = createRuntime(first.ctx, { home, wakeDebounceMs: 0 }, { callBridge: first.callBridge })
    const saved = await rt1.ensureSession('private:100000004')

    const broken = makeHost({ resolveFails: (id) => id === saved.sessionId })
    const rt2 = createRuntime(broken.ctx, { home, wakeDebounceMs: 0 }, { callBridge: broken.callBridge })
    const fresh = await rt2.ensureSession('private:100000004')
    assert.equal(broken.state.created, 1, '旧会话救不回来就新建')
    assert.notEqual(fresh.sessionId, saved.sessionId)
}

// ---- 工具面可能不在 resolveAgent 返回的 agent 上，要退回 ctx.agents ----

{
    const host = makeHost({ resolveHasTools: false, agentsHasTools: true })
    const rt = createRuntime(host.ctx, {
        home: join(process.env.DSH_HOME, 'fallback'),
        wakeDebounceMs: 0,
    }, { callBridge: host.callBridge })
    await rt.ensureSession('private:100000004')
    assert.ok(host.state.tools.has('mondchat_unread'), 'resolveAgent 不带工具面时要退回 ctx.agents')
    assert.ok(host.state.tools.has('mondchat_send'))
}

{
    const host = makeHost({ resolveHasTools: false, agentsHasTools: false })
    const rt = createRuntime(host.ctx, {
        home: join(process.env.DSH_HOME, 'no-tools'),
        wakeDebounceMs: 0,
    }, { callBridge: host.callBridge })
    await rt.ensureSession('private:1')
    assert.equal(host.state.tools.size, 0, '两边都没工具面时不抛，只是这次没挂上')
}

// ---- 服务：路由、设置、启停桥 ----

{
    const host = makeHost()
    const rt = createRuntime(host.ctx, {
        home: join(process.env.DSH_HOME, 'svc'),
        wakeDebounceMs: 0,
        retryDelayMs: 0,
        accountKey: 'test-key',
        accessToken: 'bridge-secret',
        bridge: 'ws://127.0.0.1:7788',
    }, { callBridge: host.callBridge })
    rt.ingest(message())
    await settle()
    rt.start()

    const statusRoute = host.state.routes.get('/api/mondchat/status')
    assert.ok(statusRoute, '状态路由要注册上')
    const snapshot = await (await statusRoute.fetch({})).json()
    assert.equal(snapshot.conversations.length, 1)
    assert.equal(snapshot.controls.bridge, true)
    assert.equal(snapshot.controls.inProcess, false)

    const settingsRoute = host.state.routes.get('/api/mondchat/settings')
    const gateResponse = await settingsRoute.fetch({
        json: async () => ({ gate: { conversation: 'private:100000004', idleMinutes: 7 } }),
    })
    assert.equal((await gateResponse.json()).gate.idleMinutes, 7)
    assert.equal(rt.status().conversations[0].gate.idleMinutes, 7, '每会话闸门立刻生效')

    const globalResponse = await settingsRoute.fetch({
        json: async () => ({ global: { timezone: 'Asia/Shanghai', language: 'en' } }),
    })
    assert.equal((await globalResponse.json()).reload, true, '全局设置写回 patch 会重装')
    assert.equal(host.state.edits.at(-1).config.timezone, 'Asia/Shanghai')
    assert.equal(host.state.edits.at(-1).config.language, 'en')
    assert.equal(host.state.edits.at(-1).config.bridge, 'ws://127.0.0.1:6700', '没改的字段保持原样')

    const bridgeRoute = host.state.routes.get('/api/mondchat/bridge')
    await bridgeRoute.fetch({ json: async () => ({ action: 'start' }) })
    assert.equal(host.state.processes.length, 1, '启动桥要 spawn 一次')
    assert.match(host.state.processes[0].spec.argv.join(' '), /bridge\.mjs/)
    assert.equal(host.state.processes[0].spec.env.ONEBOT_WS_PORT, '7788', '自选端口要传给子进程')
    assert.equal(host.state.processes[0].spec.env.ONEBOT_WS_HOST, '127.0.0.1')
    assert.equal(host.state.processes[0].spec.env.ONEBOT_ACCESS_TOKEN, 'bridge-secret', 'accessToken 要传给桥子进程')
    assert.equal(rt.status().bridge.process, 'running')

    await bridgeRoute.fetch({ json: async () => ({ action: 'restart' }) })
    assert.equal(host.state.processes.length, 2, '托管桥重启只换自己的子进程')
    assert.equal(host.state.processes[0].terminated, true)
    assert.equal(host.state.processes[1].terminated, false)
    assert.equal(rt.status().bridge.process, 'running')

    const badBridge = await settingsRoute.fetch({
        json: async () => ({ global: { bridge: 'http://nope' } }),
    })
    assert.equal(badBridge.status, 400, '桥地址只认 ws(s)://')

    const goodBridge = await settingsRoute.fetch({
        json: async () => ({ global: { bridge: 'ws://127.0.0.1:7789' } }),
    })
    assert.equal(goodBridge.status, 200)
    assert.equal(host.state.edits.at(-1).config.bridge, 'ws://127.0.0.1:7789')

    await bridgeRoute.fetch({ json: async () => ({ action: 'stop' }) })
    assert.equal(host.state.processes[1].terminated, true, '停止桥要 terminate')
    assert.equal(rt.status().bridge.process, 'stopped')
    rt.service.dispose()
}

// ---- 外部桥：服务层和路由都拒绝启停/重启，不能误起第二个进程 ----

{
    const host = makeHost()
    const rt = createRuntime(host.ctx, {
        home: join(process.env.DSH_HOME, 'external-bridge'),
        accountKey: 'test-key',
    }, { callBridge: host.callBridge })
    rt.service.bridgeStatus.connection = 'connected'

    await assert.rejects(() => rt.service.startBridge(), /外部桥/)
    await assert.rejects(() => rt.service.stopBridge(), /外部桥/)
    await assert.rejects(() => rt.service.restartBridge(), /托管/)
    assert.equal(rt.status().bridge.process, 'external', '拒绝操作不能把外部桥改成 stopped')

    rt.start()
    const bridgeRoute = host.state.routes.get('/api/mondchat/bridge')
    for (const action of ['start', 'stop', 'restart']) {
        const response = await bridgeRoute.fetch({ json: async () => ({ action }) })
        assert.equal(response.status, 400, `${action} 外部桥要被路由拒绝`)
    }
    assert.equal(host.state.processes.length, 0, '外部桥不能被插件再 spawn 一次')
    rt.service.dispose()
}

// ---- 真 apply()：假 WebSocket 冒充桥，走一遍真实接线 ----

class FakeSocket {
    static all = []
    constructor(url) {
        this.url = url
        this.readyState = 0
        this.listeners = {}
        this.requests = []
        FakeSocket.all.push(this)
        setTimeout(() => {
            this.readyState = 1
            this.fire('open', {})
        }, 0)
    }
    addEventListener(type, fn) {
        ;(this.listeners[type] ??= []).push(fn)
    }
    fire(type, event) {
        for (const fn of this.listeners[type] ?? []) fn(event)
    }
    send(raw) {
        const request = JSON.parse(raw)
        this.requests.push(request)
        setTimeout(() => {
            const data = request.action === 'get_user_info'
                ? { user_id: request.params.user_id, user_name: '张三' }
                : request.action === 'get_group_info'
                    ? { group_id: request.params.group_id, group_name: '测试群' }
                    : { message_id: '42', time: 1 }
            this.fire('message', {
                data: JSON.stringify({ status: 'ok', retcode: 0, data, message: '', echo: request.echo }),
            })
        }, 0)
    }
    push(event) {
        this.fire('message', { data: JSON.stringify(event) })
    }
    close() {
        this.readyState = 3
        this.fire('close', {})
    }
}

{
    globalThis.WebSocket = FakeSocket
    const host = makeHost()
    plugin.apply(host.ctx, {
        home: join(process.env.DSH_HOME, 'apply'),
        bridge: 'ws://fake-bridge:6700',
        wakeDebounceMs: 0,
    })
    await settle()

    const socket = FakeSocket.all.at(-1)
    assert.equal(socket.url, 'ws://fake-bridge:6700', 'apply 要按配置去连桥')
    assert.equal(socket.readyState, 1)

    // 桥推一条消息进来
    socket.push(message())
    await new Promise((resolve) => setTimeout(resolve, 150))
    assert.equal(host.state.prompts.length, 1, '事件经真实 WS 客户端进到插件并唤醒')

    // 工具调用经真实 WS 发出去，echo 对上才算成功
    const send = host.state.tools.get('mondchat_send')
    const sent = await send.execute({ text: '收到' }, {})
    assert.equal(sent.message_id, '42')
    assert.equal(socket.requests.at(-1).action, 'send_message')
    assert.equal(socket.requests.at(-1).params.user_id, '100000004')

    // 卸载时把工具和连接一起回收
    for (const disposer of host.state.disposers) disposer()
    assert.equal(host.state.tools.size, 0, '卸载后工具要被摘掉')
    assert.equal(socket.readyState, 3, '卸载后连接要关掉')
}

console.log('[dsh-onebot] selftest ok')
