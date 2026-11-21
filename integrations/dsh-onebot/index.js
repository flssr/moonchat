// MondChat ⇄ DSH：把 MondChat 的私聊/群接成 DSH 会话，收和发都交给 agent 自己决定。
//
// 设计前提（与本仓库 docs 一致）：
//   · 平台不替你筛消息，agent 收该账号能看到的全部会话；筛选在应用侧（这里）。
//   · 桥是 OneBot 12 实现（integrations/onebot），插件只是它的一个应用端。
//   · 每个 MondChat 私聊/群对应一个 DSH 会话；会话的权限预设统一压到只读。
//   · 不回复 = 不调 mondchat_send，不用哨兵文本，也没有自动转发。
//
// 这个文件只做装配：数据与纯逻辑在 src/model/，协议在 bridge 客户端里。

import { randomUUID } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

import { bridgeState, withConnection } from './src/model/bridge.js'
import {
  createConversation,
  describe,
  recordMessage,
  takeMessages,
  titleOf as sessionTitleOf,
} from './src/model/conversation.js'
import { formatMessages, lossNote, parseInbound } from './src/model/message.js'
import { buildWakePrompt } from './src/model/prompt.js'
import {
  gateFor,
  inQuietHours,
  normalizeGlobal,
  normalizeOverrides,
  zoneOf,
} from './src/model/settings.js'
import { inboundReason, proactiveReason } from './src/model/wake.js'

export { inQuietHours } from './src/model/settings.js'

export const name = 'mondchat-onebot'
export const inject = ['tools', 'sessions', 'sessionController']

const WAKE_DEBOUNCE_MS = 3_000
const RECONNECT_MAX_MS = 30_000
const TICK_MS = 60_000

const TOOL_UNREAD = 'mondchat_unread'
const TOOL_SEND = 'mondchat_send'
/** 面板读状态的只读路由，走共享 /api 通道（与其它插件同一套会话鉴权）。 */
const STATUS_ROUTE = '/api/mondchat/status'

const textBlock = (text) => [{ type: 'text', text: String(text) }]
// OneBot 的消息段是 {type, data}，DSH 的 ContentBlock 是 {type, text}，别混用。
const oneBotText = (text) => [{ type: 'text', data: { text: String(text) } }]

export function apply(ctx, config = {}) {
  const rt = createRuntime(ctx, config)
  rt.start()
  return rt
}

export function createRuntime(ctx, config = {}, deps = {}) {
  const log = (...args) => console.log('[mondchat]', ...args)
  const dshHome = process.env.DSH_HOME ?? join(process.env.USERPROFILE ?? '.', '.dsh')
  const home = config.home ?? join(dshHome, 'mondchat')
  const workspace = config.workspace ?? join(home, 'workspace')
  const bridgeUrl = config.bridge ?? 'ws://127.0.0.1:6700'
  const accessToken = config.accessToken ?? ''
  // 自检要跑得快：默认 3 秒去抖、15 秒重试，测试里可以压到 0。
  const wakeDebounceMs = Number(config.wakeDebounceMs ?? WAKE_DEBOUNCE_MS)
  const retryDelayMs = Number(config.retryDelayMs ?? 15_000)

  mkdirSync(workspace, { recursive: true })
  mkdirSync(home, { recursive: true })

  const statePath = join(home, 'state.json')
  const state = loadState()
  const global = normalizeGlobal(config)
  const overrides = normalizeOverrides(state.settings)

  /** conversation key → Conversation（队列、丢弃计数、DSH 会话 id 都在里面）。 */
  const conversations = new Map()
  const timers = new Map()
  /** conversation → 主动话题时间戳数组，用来卡每小时上限。 */
  const proactiveLog = new Map()
  /** `user:<id>` / `group:<id>` → 名字，带过期时间；桥拿不到就退回裸 id。 */
  const nameCache = new Map()
  /** 已经挂过工具的 agent：按对象记，会话归档后重挂时 id 不变但 agent 是新的。 */
  const registeredAgents = new WeakSet()
  const toolDisposers = []
  /** conversation → 正在建会话的 Promise，避免同一个会话被并发建两次。 */
  const opening = new Map()
  /** 运行态里和 agent 绑定的东西（不是数据，不放进 Conversation）。 */
  const agents = new Map()

  let bridgeStatus = bridgeState({ url: bridgeUrl, process: 'external', connection: 'connecting' })
  let readOnlyPreset = null
  let stopped = false

  const bridge = deps.callBridge === undefined
    ? createBridgeClient({
      url: bridgeUrl,
      token: accessToken,
      onEvent: (event) => ingest(event),
      onStatus: (connection) => {
        bridgeStatus = withConnection(bridgeStatus, connection)
      },
      log,
    })
    : { call: deps.callBridge, close() {}, state: () => bridgeStatus }

  function loadState() {
    try {
      return JSON.parse(readFileSync(statePath, 'utf8'))
    } catch {
      return { conversations: {}, settings: {} }
    }
  }

  function saveState() {
    state.settings = overrides
    try {
      writeFileSync(statePath, JSON.stringify(state, null, 2))
    } catch (error) {
      log('保存插件状态失败：', error.message)
    }
  }

  // ---- 会话实体 ----

  function conversationFor(key) {
    const existing = conversations.get(key)
    if (existing) return existing
    const saved = state.conversations?.[key]
    const created = createConversation(key, { sessionId: saved?.sessionId ?? null })
    conversations.set(key, created)
    return created
  }

  function put(next) {
    conversations.set(next.key, next)
    return next
  }

  // ---- 事件进来：排队 + 唤醒 ----

  function ingest(event) {
    const parsed = parseInbound(event, { groupsEnabled: global.groups })
    if (!parsed) return
    const next = put(recordMessage(conversationFor(parsed.conversation), parsed.message))
    scheduleWake(next.key, inboundReason(next.queue.length))
  }

  function scheduleWake(key, reason) {
    clearTimeout(timers.get(key))
    const timer = setTimeout(() => {
      timers.delete(key)
      wake(key, reason).catch((error) => log(`唤醒 ${key} 失败：`, error.message))
    }, wakeDebounceMs)
    timer.unref?.()
    timers.set(key, timer)
  }

  async function wake(key, reason) {
    const entry = await ensureSession(conversationFor(key))
    const conversation = conversationFor(key)
    const name = await displayName(conversation.kind, conversation.id)
    if (name && name !== conversation.name) put({ ...conversation, name })
    const instruction = buildWakePrompt({
      conversation: key,
      name,
      reason,
      language: global.language,
      timeZone: zoneOf(global),
    })
    try {
      await ctx.sessionController.prompt({
        requestId: randomUUID(),
        sessionId: entry.sessionId,
        mode: 'queue',
        content: textBlock(instruction),
      }, AbortSignal.timeout(30_000))
    } catch (error) {
      // 排队失败时消息还在队列里；补一次重试，否则这个会话可能永远安静下去。
      log(`唤醒 ${key} 失败，15 秒后重试：`, error.message)
      const retryKey = `retry:${key}`
      clearTimeout(timers.get(retryKey))
      const timer = setTimeout(() => {
        timers.delete(retryKey)
        wake(key, reason).catch((again) => log(`${key} 重试唤醒仍失败：`, again.message))
      }, retryDelayMs)
      timer.unref?.()
      timers.set(retryKey, timer)
    }
  }

  /**
   * 名字只是为了让 agent 读得懂，拿不到不算错：桥不可达或没这个接口就退回 id。
   * OneBot 12 的消息事件里没有 sender 对象，标准做法就是查 get_user_info。
   */
  async function displayName(kind, id) {
    const cacheKey = `${kind}:${id}`
    const cached = nameCache.get(cacheKey)
    if (cached && cached.expires > Date.now()) return cached.name
    try {
      const data = kind === 'group'
        ? await bridge.call('get_group_info', { group_id: id })
        : await bridge.call('get_user_info', { user_id: id })
      const name = String(kind === 'group' ? data?.group_name ?? '' : data?.user_name ?? '')
      if (name) nameCache.set(cacheKey, { name, expires: Date.now() + 10 * 60_000 })
      return name
    } catch {
      return ''
    }
  }

  /** 同步版：只用缓存，工具描述那种建注册时就要出字的地方用它。 */
  function labelSync(conversation) {
    const cached = nameCache.get(`${conversation.kind}:${conversation.id}`)
    const name = cached && cached.expires > Date.now() ? cached.name : conversation.name
    return describe(conversation.key, name)
  }

  // ---- DSH 会话：一个 MondChat 会话一个 ----

  async function ensureSession(conversation) {
    const key = typeof conversation === 'string' ? conversation : conversation.key
    const existing = agents.get(key)
    if (existing && conversationFor(key).sessionId && ctx.sessions.get(conversationFor(key).sessionId)) {
      return existing
    }
    const inflight = opening.get(key)
    if (inflight) return inflight

    const job = (async () => {
      // 先试映射里那个会话：DSH 重启后它是冷的，但 resolveAgent 能 resume 回来。
      const saved = state.conversations?.[key]
      if (saved?.sessionId) {
        try {
          return await adoptSession(key, saved.sessionId, { rename: false })
        } catch (error) {
          log(`${key} 的旧会话 ${saved.sessionId} 恢复不了（${error.message}），新建一个`)
          delete state.conversations[key]
          saveState()
        }
      }

      const created = await ctx.sessionController.create({ cwd: workspace })
      const sessionId = String(created.sessionId)
      state.conversations[key] = { sessionId }
      saveState()
      put({ ...conversationFor(key), sessionId })
      return adoptSession(key, sessionId, { rename: true })
    })().finally(() => opening.delete(key))

    opening.set(key, job)
    return job
  }

  async function adoptSession(key, sessionId, { rename }) {
    const resolved = await ctx.sessionController.resolveAgent(sessionId)
    if (!resolved?.agent) {
      throw new Error(`会话 ${sessionId} 恢复失败：${resolved?.error?.code ?? 'unknown'}`)
    }
    // resolveAgent 只保证能拿到 Agent；带 per-agent 工具面的那个通常从 ctx.agents 里取。
    const live = ctx.get('agents')?.get?.(sessionId)
    const agent = toolsOf(live) ? live : resolved.agent
    applyReadOnly(sessionId)
    if (global.model?.provider && global.model?.model) {
      try {
        await ctx.sessionController.selectModel({
          sessionId,
          provider: global.model.provider,
          model: global.model.model,
        })
      } catch (error) {
        log('指定模型失败，继续用会话自己的：', error.message)
      }
    }
    const disposers = registerTools(agent, key)
    const entry = { sessionId, agent, disposers }
    agents.set(key, entry)

    if (rename) {
      // 只给新建的会话起标题；恢复回来的保留用户已经改过的名字。
      try {
        await ctx.sessionController.rename({ sessionId, title: await titleOf(key) })
      } catch (error) {
        log('改会话标题失败：', error.message)
      }
    }
    return entry
  }

  async function titleOf(key) {
    const conversation = conversationFor(key)
    const name = await displayName(conversation.kind, conversation.id)
    return sessionTitleOf(key, name)
  }

  /** 统一只读：从权限预设里挑 sandbox === read-only 的那个，设不进去只告警不阻断。 */
  function applyReadOnly(sessionId) {
    const presets = ctx.get('permissionPresets')
    const session = ctx.sessions.get(sessionId)
    if (!presets || !session) return
    try {
      readOnlyPreset ??= pickReadOnly(presets)
      if (readOnlyPreset) presets.set(session, readOnlyPreset)
      else log('没有可用的只读权限预设，会话保持默认权限')
    } catch (error) {
      log('设只读预设失败：', error.message)
    }
  }

  function pickReadOnly(presets) {
    for (const option of presets.catalog()?.options ?? []) {
      try {
        if (presets.resolve(option.value)?.sandbox === 'read-only') return option.value
      } catch {
        // 解析不了就是没有这个档，继续看下一个。
      }
    }
    return null
  }

  // ---- 工具：收和发 ----

  function toolsOf(agent) {
    return agent?.ctx?.tools
  }

  function registerTools(agent, key) {
    if (registeredAgents.has(agent)) return []
    const tools = toolsOf(agent)
    if (typeof tools?.register !== 'function') {
      log(`${key} 的 agent 还不能注册工具，下一次唤醒会重试`)
      return []
    }
    registeredAgents.add(agent)
    const disposers = [tools.register(unreadTool(key)), tools.register(sendTool(key))]
    toolDisposers.push(...disposers)
    return disposers
  }

  function unreadTool(key) {
    return {
      name: TOOL_UNREAD,
      description: `读取 ${labelSync(conversationFor(key))} 里还没处理的消息。读走就清空，不重复出现。`,
      parameters: { type: 'object', properties: {}, additionalProperties: false },
      output: { schema: { type: 'string' }, render: (_args, value) => textBlock(value) },
      async execute() {
        const taken = takeMessages(conversationFor(key))
        put(taken.conversation)
        if (taken.messages.length === 0) return lossNote(taken.dropped) || '没有未读消息。'
        const senders = [...new Set(taken.messages.map((item) => item.userId))]
        const names = new Map(
          await Promise.all(senders.map(async (id) => [id, await displayName('user', id)])),
        )
        const lines = formatMessages(taken.messages, (id) => names.get(id))
        return [lossNote(taken.dropped), ...lines].filter(Boolean).join('\n')
      },
    }
  }

  function sendTool(key) {
    const conversation = conversationFor(key)
    return {
      name: TOOL_SEND,
      description: `在 ${labelSync(conversation)} 里发一条消息。不超过 500 字，超出会自动切段。`,
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
        let result
        try {
          result = await bridge.call('send_message', {
            detail_type: conversation.kind === 'group' ? 'group' : 'private',
            ...(conversation.kind === 'group' ? { group_id: conversation.id } : { user_id: conversation.id }),
            message: oneBotText(text),
          })
        } catch (error) {
          throw new Error(`没发出去：${error.message}`)
        }
        return { message_id: String(result?.message_id ?? '') }
      },
    }
  }

  // ---- 主动话题：会话安静够久就让 agent 自己决定起不起话头 ----

  function tick(now = Date.now()) {
    for (const conversation of conversations.values()) {
      const gate = gateFor(global, overrides, conversation.key)
      if (!gate.enabled) continue
      const idleSince = conversation.lastActivity || 0
      if (now - idleSince < gate.idleMinutes * 60_000) continue
      if (inQuietHours(now, gate.quietHours, zoneOf(global))) continue
      const recent = (proactiveLog.get(conversation.key) ?? []).filter((t) => now - t < 60 * 60_000)
      if (recent.length >= gate.maxPerHour) continue
      recent.push(now)
      proactiveLog.set(conversation.key, recent)
      put({ ...conversation, lastActivity: now })
      wake(conversation.key, proactiveReason(gate.idleMinutes))
        .catch((error) => log('主动话题失败：', error.message))
    }
  }

  // ---- 面板数据 ----

  function status() {
    for (const key of Object.keys(state.conversations ?? {})) conversationFor(key)
    const list = [...conversations.values()].map((conversation) => ({
      conversation: conversation.key,
      title: labelSync(conversation),
      sessionId: conversation.sessionId,
      live: Boolean(conversation.sessionId && ctx.sessions.get(conversation.sessionId)),
      unread: conversation.queue.length,
      dropped: conversation.dropped,
      lastActivity: conversation.lastActivity || null,
      gate: gateFor(global, overrides, conversation.key),
    }))
    list.sort((a, b) => (b.lastActivity ?? 0) - (a.lastActivity ?? 0))
    return {
      bridge: bridgeStatus,
      config: {
        groups: global.groups,
        workspace,
        language: global.language,
        timezone: global.timezone,
        model: global.model,
        proactive: global.proactive,
      },
      conversations: list,
    }
  }

  // ---- 启动 ----

  function start() {
    bridge.connect?.()

    // 面板的只读快照；没有 connection 的环境（比如自检）就跳过。
    const connection = ctx.get('connection')
    if (connection?.fetch?.register) {
      ctx.effect(() => connection.fetch.register({
        path: STATUS_ROUTE,
        methods: ['GET'],
        requestBody: 'buffered',
        fetch: async () => new Response(JSON.stringify(status()), {
          headers: { 'content-type': 'application/json' },
        }),
      }), 'mondchat: status route')
    }

    const timer = setInterval(() => {
      if (stopped) return
      try {
        tick()
      } catch (error) {
        log('主动话题检查失败：', error.message)
      }
    }, TICK_MS)
    timer.unref?.()

    ctx.effect(() => () => {
      stopped = true
      clearInterval(timer)
      for (const handle of timers.values()) clearTimeout(handle)
      timers.clear()
      for (const dispose of toolDisposers) dispose()
      toolDisposers.length = 0
      agents.clear()
      bridge.close?.()
    })
  }

  return {
    start,
    ingest,
    tick,
    ensureSession,
    conversationFor,
    conversations,
    state,
    status,
    settings: { global, overrides },
  }

  // ---- 桥客户端 ----

  function createBridgeClient({ url, token, onEvent: handleEvent, onStatus, log: logBridge }) {
    let socket = null
    let closed = false
    let retryMs = 1_000
    let reconnectTimer = null
    let seq = 0
    const pending = new Map()

    function connect() {
      if (closed) return
      const target = token ? `${url}${url.includes('?') ? '&' : '?'}access_token=${encodeURIComponent(token)}` : url
      onStatus('connecting')
      socket = new WebSocket(target)
      socket.addEventListener('open', () => {
        retryMs = 1_000
        onStatus('connected')
        logBridge(`已连上桥 ${url}`)
      })
      socket.addEventListener('message', (event) => {
        let data = null
        try {
          data = JSON.parse(String(event.data))
        } catch {
          return
        }
        if (data.echo !== undefined && pending.has(data.echo)) {
          const settle = pending.get(data.echo)
          pending.delete(data.echo)
          settle(data)
          return
        }
        if (data.type === 'meta') return
        handleEvent(data)
      })
      socket.addEventListener('close', () => {
        onStatus('disconnected')
        if (closed) return
        reconnectTimer = setTimeout(connect, retryMs)
        reconnectTimer.unref?.()
        retryMs = Math.min(retryMs * 2, RECONNECT_MAX_MS)
      })
      socket.addEventListener('error', () => {})
    }

    function call(action, params) {
      return new Promise((resolve, reject) => {
        if (!socket || socket.readyState !== 1) {
          reject(new Error('桥还没连上'))
          return
        }
        const echo = String(++seq)
        pending.set(echo, (data) => {
          if (data.status === 'ok') resolve(data.data)
          else reject(new Error(`${data.retcode}: ${data.message}`))
        })
        socket.send(JSON.stringify({ action, params, echo }))
        setTimeout(() => {
          if (pending.delete(echo)) reject(new Error(`动作超时：${action}`))
        }, 15_000).unref?.()
      })
    }

    return {
      connect,
      call,
      state: () => bridgeStatus,
      close: () => {
        closed = true
        clearTimeout(reconnectTimer)
        socket?.close()
      },
    }
  }
}
