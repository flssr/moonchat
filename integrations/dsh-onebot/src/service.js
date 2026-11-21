// MondChat 的用例层：持有会话、桥、设置与定时器，对外只暴露状态与操作。
// 路由、工具、面板都调这里；它自己不认 HTTP，也不知道槽位。

import { randomUUID } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { createBridgeClient } from './bridge/client.js'
import { bridgeState, withConnection, withProcess } from './model/bridge.js'
import {
    createConversation,
    describe,
    recordMessage,
    takeMessages,
    titleOf as sessionTitleOf,
} from './model/conversation.js'
import { parseInbound } from './model/message.js'
import { buildWakePrompt } from './model/prompt.js'
import {
    LANGUAGES,
    gateFor,
    inQuietHours,
    normalizeGlobal,
    normalizeOverrides,
    zoneOf,
} from './model/settings.js'
import { inboundReason, proactiveReason } from './model/wake.js'
import { registerTools } from './tools.js'

const WAKE_DEBOUNCE_MS = 3_000
const TICK_MS = 60_000
const PLUGIN_DIR = dirname(dirname(fileURLToPath(import.meta.url)))

export class MondChatService {
    constructor({ ctx, config = {}, deps = {}, log = (...args) => console.log('[mondchat]', ...args) }) {
        this.ctx = ctx
        this.config = config
        this.log = log

        const dshHome = process.env.DSH_HOME ?? join(process.env.USERPROFILE ?? '.', '.dsh')
        this.home = config.home ?? join(dshHome, 'mondchat')
        this.workspace = config.workspace ?? join(this.home, 'workspace')
        this.bridgeUrl = config.bridge ?? 'ws://127.0.0.1:6700'
        this.accessToken = config.accessToken ?? ''
        this.wakeDebounceMs = Number(config.wakeDebounceMs ?? WAKE_DEBOUNCE_MS)
        this.retryDelayMs = Number(config.retryDelayMs ?? 15_000)
        // 桥地址是唯一真相：托管桥时按它推导子进程的 host/port。
        this.bridgeHost = hostOf(this.bridgeUrl, '127.0.0.1')
        this.bridgePort = portOf(this.bridgeUrl, 6700)

        // 启停桥：默认用跑 DSH 的同一个 node 执行仓库里的桥脚本。
        this.bridgeScript = config.bridgeScript ?? join(PLUGIN_DIR, '..', 'onebot', 'bridge.mjs')
        this.bridgeCommand = Array.isArray(config.bridgeCommand) && config.bridgeCommand.length > 0
            ? config.bridgeCommand.map(String)
            : [process.execPath, this.bridgeScript]
        this.accountKeyFile = config.accountKeyFile
            ?? join(process.env.USERPROFILE ?? process.env.HOME ?? '.', '.mondchat.key')
        this.apiBase = config.apiBase ?? 'https://api.mondchat.com'
        this.subprocessHandle = null

        mkdirSync(this.workspace, { recursive: true })
        mkdirSync(this.home, { recursive: true })

        this.statePath = join(this.home, 'state.json')
        this.state = this.loadState()
        this.global = normalizeGlobal(config)
        this.overrides = normalizeOverrides(this.state.settings)

        /** conversation key → Conversation（队列、丢弃、DSH 会话 id 都在里面）。 */
        this.conversations = new Map()
        /** 运行态里和 agent 绑定的东西，不进实体。 */
        this.agents = new Map()
        this.timers = new Map()
        this.proactiveLog = new Map()
        this.nameCache = new Map()
        this.registeredAgents = new WeakSet()
        this.toolDisposers = []
        this.opening = new Map()
        this.readOnlyPreset = null
        this.stopped = false
        this.timer = null
        this.bridgeStatus = bridgeState({
            url: this.bridgeUrl,
            process: 'external',
            connection: 'connecting',
        })

        this.bridge = deps.callBridge === undefined
            ? createBridgeClient({
                url: this.bridgeUrl,
                token: this.accessToken,
                onEvent: (event) => this.ingest(event),
                onStatus: (connection) => {
                    this.bridgeStatus = withConnection(this.bridgeStatus, connection)
                },
                log: this.log,
            })
            : { call: deps.callBridge, connect() {}, close() {} }
    }

    // ---- 生命周期 ----

    start() {
        this.bridge.connect?.()
        this.timer = setInterval(() => {
            if (this.stopped) return
            try {
                this.tick()
            } catch (error) {
                this.log('主动话题检查失败：', error.message)
            }
        }, TICK_MS)
        this.timer.unref?.()
        return this
    }

    dispose() {
        this.stopped = true
        clearInterval(this.timer)
        for (const handle of this.timers.values()) clearTimeout(handle)
        this.timers.clear()
        for (const dispose of this.toolDisposers) dispose()
        this.toolDisposers.length = 0
        this.agents.clear()
        // 自己起的桥要跟着走，别留孤儿进程。
        this.subprocessHandle?.terminate()
        this.subprocessHandle = null
        this.bridge.close?.()
    }

    // ---- 桥进程 ----

    /** 密钥只从 config 或文件读，不落日志、不进 state。 */
    accountKey() {
        if (typeof this.config.accountKey === 'string' && this.config.accountKey.trim()) {
            return this.config.accountKey.trim()
        }
        try {
            return readFileSync(this.accountKeyFile, 'utf8').trim()
        } catch {
            return ''
        }
    }

    canManageBridge() {
        return typeof this.ctx.get('subprocess')?.spawn === 'function'
    }

    async startBridge() {
        if (!this.canManageBridge()) throw new Error('宿主没有 subprocess 服务，不能启停桥')
        if (this.subprocessHandle) return this.bridgeStatus
        const key = this.accountKey()
        if (!key) throw new Error(`没有账号密钥：填 config.accountKey 或写 ${this.accountKeyFile}`)

        this.bridgeStatus = withProcess(this.bridgeStatus, 'starting')
        let handle
        try {
            handle = this.ctx.get('subprocess').spawn({
                argv: this.bridgeCommand,
                cwd: dirname(this.bridgeScript),
                stdio: {
                    stdin: 'ignore',
                    stdout: { maxBytes: 64 * 1024 },
                    stderr: { maxBytes: 64 * 1024 },
                },
                graceMs: 5_000,
                env: {
                    ...process.env,
                    MONDCHAT_ACCOUNT_KEY: key,
                    MONDCHAT_API_BASE: this.apiBase,
                    // 自选端口：子进程绑定的就是配置里那个地址。
                    ONEBOT_WS_HOST: this.bridgeHost,
                    ONEBOT_WS_PORT: String(this.bridgePort),
                },
            })
        } catch (error) {
            this.bridgeStatus = withProcess(this.bridgeStatus, 'failed', error.message)
            throw error
        }

        this.subprocessHandle = handle
        this.bridgeStatus = withProcess(this.bridgeStatus, 'running')
        handle.done.then((outcome) => {
            this.subprocessHandle = null
            const failed = outcome.exitCode !== 0
            this.bridgeStatus = withProcess(
                this.bridgeStatus,
                failed ? 'failed' : 'stopped',
                failed ? `退出码 ${outcome.exitCode}` : '',
            )
        }).catch((error) => {
            this.subprocessHandle = null
            this.bridgeStatus = withProcess(this.bridgeStatus, 'failed', error.message)
        })
        return this.bridgeStatus
    }

    async stopBridge() {
        const handle = this.subprocessHandle
        if (!handle) {
            this.bridgeStatus = withProcess(this.bridgeStatus, 'stopped')
            return this.bridgeStatus
        }
        this.subprocessHandle = null
        handle.terminate()
        await handle.waitForExit().catch(() => {})
        this.bridgeStatus = withProcess(this.bridgeStatus, 'stopped')
        return this.bridgeStatus
    }

    // ---- 设置 ----

    /** 全局项进 profile patch：改完 Loader 会重装插件（桥跟着重连一次）。 */
    async setGlobal(patch = {}) {
        const editor = this.ctx.get('configEditor')
        if (typeof editor?.edit !== 'function' || typeof editor?.entries !== 'function') {
            throw new Error('宿主没有 configEditor，不能改全局设置')
        }
        const entries = editor.entries()
        const entry = entries.find((item) => item.id === 'mondchat-onebot')
            ?? entries.find((item) => item.name === 'dsh-onebot')
        if (!entry) throw new Error('找不到插件在 profile 里的配置项')

        const next = {}
        if (patch.bridge !== undefined) next.bridge = normalizeBridgeUrl(patch.bridge)
        if (patch.timezone !== undefined) next.timezone = String(patch.timezone ?? '')
        if (patch.language !== undefined) {
            next.language = LANGUAGES.includes(patch.language) ? patch.language : this.global.language
        }
        if (patch.groups !== undefined) next.groups = Boolean(patch.groups)
        if (Object.keys(next).length === 0) throw new Error('没有可改的全局设置')

        await editor.edit(entry, (current) => ({ ...current, ...next }))
        return next
    }

    /** 每会话闸门进 state.json：立即生效，不重装插件。 */
    setGate(key, patch = {}) {
        this.conversationFor(key)
        const clean = {}
        if (typeof patch.enabled === 'boolean') clean.enabled = patch.enabled
        if (Number.isFinite(Number(patch.idleMinutes)) && Number(patch.idleMinutes) > 0) {
            clean.idleMinutes = Number(patch.idleMinutes)
        }
        if (Number.isFinite(Number(patch.maxPerHour)) && Number(patch.maxPerHour) > 0) {
            clean.maxPerHour = Number(patch.maxPerHour)
        }
        if (typeof patch.quietHours === 'string') clean.quietHours = patch.quietHours

        // 空值 = 清掉这个会话的覆盖，回到全局。
        if (Object.keys(clean).length === 0) delete this.overrides[key]
        else this.overrides[key] = { ...this.overrides[key], ...clean }
        this.saveState()
        return gateFor(this.global, this.overrides, key)
    }

    // ---- 状态读写 ----

    loadState() {
        try {
            return JSON.parse(readFileSync(this.statePath, 'utf8'))
        } catch {
            return { conversations: {}, settings: {} }
        }
    }

    saveState() {
        this.state.settings = this.overrides
        try {
            writeFileSync(this.statePath, JSON.stringify(this.state, null, 2))
        } catch (error) {
            this.log('保存插件状态失败：', error.message)
        }
    }

    conversationFor(key) {
        const existing = this.conversations.get(key)
        if (existing) return existing
        const saved = this.state.conversations?.[key]
        const created = createConversation(key, { sessionId: saved?.sessionId ?? null })
        this.conversations.set(key, created)
        return created
    }

    put(next) {
        this.conversations.set(next.key, next)
        return next
    }

    // ---- 入站与唤醒 ----

    ingest(event) {
        const parsed = parseInbound(event, { groupsEnabled: this.global.groups })
        if (!parsed) return
        const next = this.put(recordMessage(this.conversationFor(parsed.conversation), parsed.message))
        this.scheduleWake(next.key, inboundReason(next.queue.length))
    }

    scheduleWake(key, reason) {
        clearTimeout(this.timers.get(key))
        const timer = setTimeout(() => {
            this.timers.delete(key)
            this.wake(key, reason).catch((error) => this.log(`唤醒 ${key} 失败：`, error.message))
        }, this.wakeDebounceMs)
        timer.unref?.()
        this.timers.set(key, timer)
    }

    async wake(key, reason) {
        const entry = await this.ensureSession(this.conversationFor(key))
        const conversation = this.conversationFor(key)
        const name = await this.displayName(conversation.kind, conversation.id)
        if (name && name !== conversation.name) this.put({ ...conversation, name })
        const instruction = buildWakePrompt({
            conversation: key,
            name,
            reason,
            language: this.global.language,
            timeZone: zoneOf(this.global),
        })
        try {
            await this.ctx.sessionController.prompt({
                requestId: randomUUID(),
                sessionId: entry.sessionId,
                mode: 'queue',
                content: [{ type: 'text', text: instruction }],
            }, AbortSignal.timeout(30_000))
        } catch (error) {
            // 排队失败时消息还在队列里；补一次重试，否则这个会话可能永远安静下去。
            this.log(`唤醒 ${key} 失败，15 秒后重试：`, error.message)
            const retryKey = `retry:${key}`
            clearTimeout(this.timers.get(retryKey))
            const timer = setTimeout(() => {
                this.timers.delete(retryKey)
                this.wake(key, reason).catch((again) => this.log(`${key} 重试唤醒仍失败：`, again.message))
            }, this.retryDelayMs)
            timer.unref?.()
            this.timers.set(retryKey, timer)
        }
    }

    /**
     * 名字只是为了让 agent 读得懂，拿不到不算错：桥不可达或没这个接口就退回 id。
     * OneBot 12 的消息事件里没有 sender 对象，标准做法就是查 get_user_info。
     */
    async displayName(kind, id) {
        const cacheKey = `${kind}:${id}`
        const cached = this.nameCache.get(cacheKey)
        if (cached && cached.expires > Date.now()) return cached.name
        try {
            const data = kind === 'group'
                ? await this.bridge.call('get_group_info', { group_id: id })
                : await this.bridge.call('get_user_info', { user_id: id })
            const name = String(kind === 'group' ? data?.group_name ?? '' : data?.user_name ?? '')
            if (name) this.nameCache.set(cacheKey, { name, expires: Date.now() + 10 * 60_000 })
            return name
        } catch {
            return ''
        }
    }

    /** 同步版：只用缓存，工具描述那种注册时就要出字的地方用它。 */
    labelFor(key) {
        const conversation = this.conversationFor(key)
        const cached = this.nameCache.get(`${conversation.kind}:${conversation.id}`)
        const name = cached && cached.expires > Date.now() ? cached.name : conversation.name
        return describe(key, name)
    }

    // ---- DSH 会话 ----

    async ensureSession(conversation) {
        const key = typeof conversation === 'string' ? conversation : conversation.key
        const current = this.conversationFor(key)
        const existing = this.agents.get(key)
        if (existing && current.sessionId && this.ctx.sessions.get(current.sessionId)) return existing

        const inflight = this.opening.get(key)
        if (inflight) return inflight

        const job = (async () => {
            // 先试映射里那个会话：DSH 重启后它是冷的，但 resolveAgent 能 resume 回来。
            const saved = this.state.conversations?.[key]
            if (saved?.sessionId) {
                try {
                    return await this.adoptSession(key, saved.sessionId, { rename: false })
                } catch (error) {
                    this.log(`${key} 的旧会话 ${saved.sessionId} 恢复不了（${error.message}），新建一个`)
                    delete this.state.conversations[key]
                    this.saveState()
                }
            }

            const created = await this.ctx.sessionController.create({ cwd: this.workspace })
            const sessionId = String(created.sessionId)
            this.state.conversations[key] = { sessionId }
            this.saveState()
            this.put({ ...this.conversationFor(key), sessionId })
            return this.adoptSession(key, sessionId, { rename: true })
        })().finally(() => this.opening.delete(key))

        this.opening.set(key, job)
        return job
    }

    async adoptSession(key, sessionId, { rename }) {
        const resolved = await this.ctx.sessionController.resolveAgent(sessionId)
        if (!resolved?.agent) {
            throw new Error(`会话 ${sessionId} 恢复失败：${resolved?.error?.code ?? 'unknown'}`)
        }
        // resolveAgent 只保证能拿到 Agent；带 per-agent 工具面的那个通常从 ctx.agents 里取。
        const live = this.ctx.get('agents')?.get?.(sessionId)
        const agent = live?.ctx?.tools ? live : resolved.agent
        this.applyReadOnly(sessionId)
        if (this.global.model?.provider && this.global.model?.model) {
            try {
                await this.ctx.sessionController.selectModel({
                    sessionId,
                    provider: this.global.model.provider,
                    model: this.global.model.model,
                })
            } catch (error) {
                this.log('指定模型失败，继续用会话自己的：', error.message)
            }
        }
        const entry = { sessionId, agent, disposers: this.attachTools(agent, key) }
        this.agents.set(key, entry)

        if (rename) {
            // 只给新建的会话起标题；恢复回来的保留用户已经改过的名字。
            try {
                await this.ctx.sessionController.rename({ sessionId, title: await this.sessionTitle(key) })
            } catch (error) {
                this.log('改会话标题失败：', error.message)
            }
        }
        return entry
    }

    async sessionTitle(key) {
        const conversation = this.conversationFor(key)
        return sessionTitleOf(key, await this.displayName(conversation.kind, conversation.id))
    }

    attachTools(agent, key) {
        if (this.registeredAgents.has(agent)) return []
        if (typeof agent?.ctx?.tools?.register !== 'function') {
            this.log(`${key} 的 agent 还不能注册工具，下一次唤醒会重试`)
            return []
        }
        this.registeredAgents.add(agent)
        const disposers = registerTools(agent, key, this)
        this.toolDisposers.push(...disposers)
        return disposers
    }

    /** 统一只读：从权限预设里挑 sandbox === read-only 的那个，设不进去只告警不阻断。 */
    applyReadOnly(sessionId) {
        const presets = this.ctx.get('permissionPresets')
        const session = this.ctx.sessions.get(sessionId)
        if (!presets || !session) return
        try {
            this.readOnlyPreset ??= this.pickReadOnly(presets)
            if (this.readOnlyPreset) presets.set(session, this.readOnlyPreset)
            else this.log('没有可用的只读权限预设，会话保持默认权限')
        } catch (error) {
            this.log('设只读预设失败：', error.message)
        }
    }

    pickReadOnly(presets) {
        for (const option of presets.catalog()?.options ?? []) {
            try {
                if (presets.resolve(option.value)?.sandbox === 'read-only') return option.value
            } catch {
                // 解析不了就是没有这个档，继续看下一个。
            }
        }
        return null
    }

    // ---- 工具用例 ----

    takeMessages(key) {
        const taken = takeMessages(this.conversationFor(key))
        this.put(taken.conversation)
        return { messages: taken.messages, dropped: taken.dropped }
    }

    async send(key, segments) {
        const conversation = this.conversationFor(key)
        const result = await this.bridge.call('send_message', {
            detail_type: conversation.kind === 'group' ? 'group' : 'private',
            ...(conversation.kind === 'group' ? { group_id: conversation.id } : { user_id: conversation.id }),
            message: segments,
        })
        return { message_id: String(result?.message_id ?? '') }
    }

    // ---- 主动话题 ----

    tick(now = Date.now()) {
        for (const conversation of this.conversations.values()) {
            const gate = gateFor(this.global, this.overrides, conversation.key)
            if (!gate.enabled) continue
            const idleSince = conversation.lastActivity || 0
            if (now - idleSince < gate.idleMinutes * 60_000) continue
            if (inQuietHours(now, gate.quietHours, zoneOf(this.global))) continue
            const recent = (this.proactiveLog.get(conversation.key) ?? []).filter((t) => now - t < 60 * 60_000)
            if (recent.length >= gate.maxPerHour) continue
            recent.push(now)
            this.proactiveLog.set(conversation.key, recent)
            this.put({ ...conversation, lastActivity: now })
            this.wake(conversation.key, proactiveReason(gate.idleMinutes))
                .catch((error) => this.log('主动话题失败：', error.message))
        }
    }

    // ---- 对外快照（路由与面板用）----

    status() {
        for (const key of Object.keys(this.state.conversations ?? {})) this.conversationFor(key)
        const list = [...this.conversations.values()].map((conversation) => ({
            conversation: conversation.key,
            title: this.labelFor(conversation.key),
            sessionId: conversation.sessionId,
            live: Boolean(conversation.sessionId && this.ctx.sessions.get(conversation.sessionId)),
            unread: conversation.queue.length,
            dropped: conversation.dropped,
            lastActivity: conversation.lastActivity || null,
            gate: gateFor(this.global, this.overrides, conversation.key),
        }))
        list.sort((a, b) => (b.lastActivity ?? 0) - (a.lastActivity ?? 0))
        return {
            bridge: this.bridgeStatus,
            controls: {
                bridge: this.canManageBridge(),
                inProcess: Boolean(this.subprocessHandle),
                bridgeScript: this.bridgeScript,
                accountKeyFile: this.accountKeyFile,
                apiBase: this.apiBase,
                host: this.bridgeHost,
                port: this.bridgePort,
            },
            config: {
                groups: this.global.groups,
                workspace: this.workspace,
                language: this.global.language,
                timezone: this.global.timezone,
                model: this.global.model,
                proactive: this.global.proactive,
            },
            conversations: list,
        }
    }
}

function hostOf(url, fallback) {
    try {
        return new URL(String(url)).hostname || fallback
    } catch {
        return fallback
    }
}

/** 没写端口时用桥的默认 6700，而不是 ws 协议默认的 80。 */
function portOf(url, fallback) {
    try {
        const port = new URL(String(url)).port
        return port ? Number(port) : fallback
    } catch {
        return fallback
    }
}

function normalizeBridgeUrl(value) {
    const url = String(value ?? '').trim()
    if (!/^wss?:\/\//i.test(url)) throw new Error('桥地址必须以 ws:// 或 wss:// 开头')
    try {
        new URL(url)
    } catch {
        throw new Error(`桥地址解析不了：${url}`)
    }
    return url
}
