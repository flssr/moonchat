// MondChat ⇄ DSH：把 MondChat 的私聊/群接成 DSH 会话，收和发都交给 agent 自己决定。
//
// 设计前提（与本仓库 docs 一致）：
//   · 平台不替你筛消息，agent 收该账号能看到的全部会话；筛选在应用侧（这里）。
//   · 桥是 OneBot 12 实现（integrations/onebot），插件只是它的一个应用端。
//   · 每个 MondChat 私聊/群对应一个 DSH 会话；会话的权限预设统一压到只读。
//   · 不回复 = 不调 mondchat_send，不用哨兵文本，也没有自动转发。
//
// 挂载（profile 的 cordis.patch.yml）：
//   - id: mondchat-onebot
//     name: dsh-onebot
//     config:
//       bridge: ws://127.0.0.1:6700

import { randomUUID } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

export const name = 'mondchat-onebot'
export const inject = ['tools', 'sessions', 'sessionController']

const CONVERSATION = /^(private|group):(\d+)$/
const WAKE_DEBOUNCE_MS = 3_000
const RECONNECT_MAX_MS = 30_000
const TICK_MS = 60_000

const TOOL_UNREAD = 'mondchat_unread'
const TOOL_SEND = 'mondchat_send'

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
  const groupsEnabled = config.groups !== false
  // 自检要跑得快：默认 3 秒去抖、15 秒重试，测试里可以压到 0。
  const wakeDebounceMs = Number(config.wakeDebounceMs ?? WAKE_DEBOUNCE_MS)
  const retryDelayMs = Number(config.retryDelayMs ?? 15_000)
  const proactiveConfig = {
    enabled: config.proactive?.enabled !== false,
    idleMinutes: Number(config.proactive?.idleMinutes ?? 60),
    maxPerHour: Number(config.proactive?.maxPerHour ?? 2),
    quietHours: config.proactive?.quietHours ?? '23:00-08:00',
  }

  mkdirSync(workspace, { recursive: true })
  mkdirSync(home, { recursive: true })

  const statePath = join(home, 'state.json')
  const state = loadState()

  /** conversation → 待处理消息（只活在内存里；桥不回填历史，重启就没了）。 */
  const inbox = new Map()
  /** conversation → { sessionId, tools: [] } */
  const sessions = new Map()
  /** conversation → 最后一次有人说话的时间戳，主动话题用 */
  const lastActivity = new Map()
  /** `user:<id>` / `group:<id>` → 名字，带过期时间；桥拿不到就退回裸 id。 */
  const nameCache = new Map()
  /** conversation → 主动话题时间戳数组，用来卡每小时上限 */
  const proactiveLog = new Map()
  const timers = new Map()
  /** 已经挂过工具的 agent，避免重载或重复 adopt 时重复注册（同一层重名会抛）。 */
  const registeredAgents = new Set()
  const toolDisposers = []
  let readOnlyPreset = null
  let stopped = false

  // ---- 桥客户端（deps.callBridge 可替换，自检用）----

  const bridge = deps.callBridge === undefined
    ? createBridgeClient({ url: bridgeUrl, token: accessToken, onEvent: (event) => ingest(event), log })
    : { call: deps.callBridge, close() {} }

  function loadState() {
    try {
      return JSON.parse(readFileSync(statePath, 'utf8'))
    } catch {
      return { conversations: {} }
    }
  }

  function saveState() {
    try {
      writeFileSync(statePath, JSON.stringify(state, null, 2))
    } catch (error) {
      log('保存会话映射失败：', error.message)
    }
  }

  // ---- 事件进来：排队 + 唤醒 ----

  function ingest(event) {
    if (!event || event.type !== 'message') return
    const isGroup = event.detail_type === 'group'
    if (isGroup && !groupsEnabled) return
    const id = isGroup ? String(event.group_id ?? '') : String(event.user_id ?? '')
    if (!id || !event.user_id) return
    const conversation = `${isGroup ? 'group' : 'private'}:${id}`
    const text = (event.message ?? [])
      .filter((segment) => segment?.type === 'text')
      .map((segment) => String(segment.data?.text ?? ''))
      .join('')
    if (!text.trim()) return

    const queue = inbox.get(conversation) ?? []
    queue.push({
      message_id: String(event.message_id ?? ''),
      user_id: String(event.user_id),
      time: Number(event.time ?? 0),
      text: text.slice(0, 2_000),
    })
    inbox.set(conversation, queue.slice(-50))
    lastActivity.set(conversation, Date.now())
    scheduleWake(conversation, `${text.length > 0 ? '有新消息' : ''}（${queue.length} 条）`)
  }

  function scheduleWake(conversation, reason) {
    clearTimeout(timers.get(conversation))
    const timer = setTimeout(() => {
      timers.delete(conversation)
      wake(conversation, reason).catch((error) => log(`唤醒 ${conversation} 失败：`, error.message))
    }, wakeDebounceMs)
    timer.unref?.()
    timers.set(conversation, timer)
  }

  async function wake(conversation, reason) {
    const entry = await ensureSession(conversation)
    const instruction = isProactive(reason)
      ? `【MondChat 群】这个群安静了至少 ${proactiveConfig.idleMinutes} 分钟。你可以用 ${TOOL_SEND} 起个话头；没有想说的就别动。`
      : `【MondChat】${await labelOf(conversation)}${reason}。用 ${TOOL_UNREAD} 看内容；想发言就调 ${TOOL_SEND}，不想发言就不用调。发言用中文、口语，一条不超过 200 字。`
    try {
      await ctx.sessionController.prompt({
        requestId: randomUUID(),
        sessionId: entry.sessionId,
        mode: 'queue',
        content: textBlock(instruction),
      }, AbortSignal.timeout(30_000))
    } catch (error) {
      // 排队失败时消息还在队列里；补一次重试，否则这个会话可能永远安静下去。
      log(`唤醒 ${conversation} 失败，15 秒后重试：`, error.message)
      const retryKey = `retry:${conversation}`
      clearTimeout(timers.get(retryKey))
      const timer = setTimeout(() => {
        timers.delete(retryKey)
        wake(conversation, reason).catch((again) => log(`${conversation} 重试唤醒仍失败：`, again.message))
      }, retryDelayMs)
      timer.unref?.()
      timers.set(retryKey, timer)
    }
  }

  const isProactive = (reason) => String(reason).startsWith('proactive')

  /**
   * 名字只是为了让 agent 读得懂，拿不到不算错：桥不可达或没这个接口就退回 id。
   * OneBot 12 的消息事件里没有 sender 对象，标准做法就是查 get_user_info。
   */
  async function displayName(kind, id) {
    const key = `${kind}:${id}`
    const cached = nameCache.get(key)
    if (cached && cached.expires > Date.now()) return cached.name
    try {
      const data = kind === 'group'
        ? await bridge.call('get_group_info', { group_id: id })
        : await bridge.call('get_user_info', { user_id: id })
      const name = String(kind === 'group' ? data?.group_name ?? '' : data?.user_name ?? '')
      if (name) nameCache.set(key, { name, expires: Date.now() + 10 * 60_000 })
      return name
    } catch {
      return ''
    }
  }

  async function labelOf(conversation) {
    const [kind, id] = conversation.split(':')
    await displayName(kind, id)
    return labelSync(conversation)
  }

  /** 侧栏里认得出的标题：MondChat 的私聊/群叫什么。 */
  async function titleOf(conversation) {
    const [kind, id] = conversation.split(':')
    const name = await displayName(kind, id)
    if (kind === 'group') return name ? `MondChat · 群「${name}」` : `MondChat · 群 ${id}`
    return name ? `MondChat · 与 ${name} 的私聊` : `MondChat · 与 ${id} 的私聊`
  }

  /** 同步版：只用缓存，工具描述那种建注册时就要出字的地方用它。 */
  function labelSync(conversation) {
    const [kind, id] = conversation.split(':')
    const cached = nameCache.get(`${kind}:${id}`)
    const name = cached && cached.expires > Date.now() ? cached.name : ''
    if (kind === 'group') return name ? `群「${name}」(${id})` : `群 ${id}`
    return name ? `与「${name}」(${id}) 的私聊` : `与 ${id} 的私聊`
  }

  // ---- 会话：一个 MondChat 会话一个 DSH 会话 ----

  /** conversation → 正在建会话的 Promise，避免同一个会话被并发建两次。 */
  const opening = new Map()

  async function ensureSession(conversation) {
    const existing = sessions.get(conversation)
    if (existing && ctx.sessions.get(existing.sessionId)) return existing

    const inflight = opening.get(conversation)
    if (inflight) return inflight

    const job = (async () => {
      // 先试映射里那个会话：DSH 重启后它是冷的（不在 ctx.sessions 里），
      // 但 resolveAgent 能把它resume 回来，不能因为"不在内存"就当没有。
      const saved = state.conversations[conversation]
      if (saved?.sessionId) {
        try {
          const entry = await adoptSession(conversation, saved.sessionId)
          sessions.set(conversation, entry)
          return entry
        } catch (error) {
          log(`${conversation} 的旧会话 ${saved.sessionId} 恢复不了（${error.message}），新建一个`)
          delete state.conversations[conversation]
          saveState()
        }
      }

      const created = await ctx.sessionController.create({ cwd: workspace })
      const sessionId = String(created.sessionId)
      state.conversations[conversation] = { sessionId }
      saveState()

      const entry = await adoptSession(conversation, sessionId)
      // 只给新建的会话起标题；恢复回来的保留用户已经改过的名字。
      try {
        await ctx.sessionController.rename({ sessionId, title: await titleOf(conversation) })
      } catch (error) {
        log('改会话标题失败：', error.message)
      }
      sessions.set(conversation, entry)
      log(`${conversation} → 会话 ${sessionId}`)
      return entry
    })().finally(() => opening.delete(conversation))

    opening.set(conversation, job)
    return job
  }

  async function adoptSession(conversation, sessionId) {
    const resolved = await ctx.sessionController.resolveAgent(sessionId)
    if (!resolved?.agent) {
      throw new Error(`会话 ${sessionId} 恢复失败：${resolved?.error?.code ?? 'unknown'}`)
    }
    // resolveAgent 只保证能拿到 Agent；带 per-agent 工具面的那个通常从 ctx.agents 里取
    // （ds-bot 也是这么拿的）。两边都试，谁有 tools 用谁。
    const live = ctx.get('agents')?.get?.(sessionId)
    const agent = toolsOf(live) ? live : resolved.agent
    applyReadOnly(sessionId)
    if (config.model?.provider && config.model?.model) {
      try {
        await ctx.sessionController.selectModel({
          sessionId,
          provider: config.model.provider,
          model: config.model.model,
        })
      } catch (error) {
        log('指定模型失败，继续用会话自己的：', error.message)
      }
    }
    const disposers = registerTools(agent, conversation)
    return { sessionId, agent, disposers }
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
        const spec = presets.resolve(option.value)
        if (spec?.sandbox === 'read-only') return option.value
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

  function registerTools(agent, conversation) {
    if (registeredAgents.has(agent.id)) return []
    const tools = toolsOf(agent)
    if (typeof tools?.register !== 'function') {
      log(`${conversation} 的 agent 还不能注册工具，下一次唤醒会重试`)
      return []
    }
    registeredAgents.add(agent.id)
    const disposers = [tools.register(unreadTool(conversation)), tools.register(sendTool(conversation))]
    toolDisposers.push(...disposers)
    return disposers
  }

  function unreadTool(conversation) {
    return {
      name: TOOL_UNREAD,
      description: `读取 ${labelSync(conversation)} 里还没处理的消息。读走就清空，不重复出现。`,
      parameters: { type: 'object', properties: {}, additionalProperties: false },
      output: {
        schema: { type: 'string' },
        render: (_args, value) => textBlock(value),
      },
      async execute() {
        const queue = inbox.get(conversation) ?? []
        inbox.delete(conversation)
        if (queue.length === 0) return '没有未读消息。'
        const senders = [...new Set(queue.map((item) => item.user_id))]
        const names = new Map(
          await Promise.all(senders.map(async (id) => [id, await displayName('user', id)])),
        )
        return queue.map((item) => {
          const at = item.time ? new Date(item.time * 1000).toISOString() : ''
          const who = names.get(item.user_id)
          return `[${at}] ${who ? `${who}(${item.user_id})` : item.user_id}: ${item.text}`
        }).join('\n')
      },
    }
  }

  function sendTool(conversation) {
    const [kind, id] = conversation.split(':')
    return {
      name: TOOL_SEND,
      description: `在 ${labelSync(conversation)} 里发一条消息。不超过 500 字，超出会自动切段。`,
      parameters: {
        type: 'object',
        properties: {
          text: { type: 'string', description: '要发的内容' },
        },
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
            detail_type: kind === 'group' ? 'group' : 'private',
            ...(kind === 'group' ? { group_id: id } : { user_id: id }),
            message: oneBotText(text),
          })
        } catch (error) {
          throw new Error(`没发出去：${error.message}`)
        }
        return { message_id: String(result?.message_id ?? '') }
      },
    }
  }

  // ---- 主动话题：群里安静太久就给它一次机会 ----

  function tick(now = Date.now()) {
    if (!proactiveConfig.enabled) return
    if (!groupsEnabled) return
    // 只在真的见过消息的群上起话头：桥只推事件，没推过的群我们也不认识。
    for (const conversation of lastActivity.keys()) {
      if (!conversation.startsWith('group:')) continue
      const idleSince = lastActivity.get(conversation) ?? 0
      if (now - idleSince < proactiveConfig.idleMinutes * 60_000) continue
      if (inQuietHours(now, proactiveConfig.quietHours)) continue
      const recent = (proactiveLog.get(conversation) ?? []).filter((t) => now - t < 60 * 60_000)
      if (recent.length >= proactiveConfig.maxPerHour) continue
      recent.push(now)
      proactiveLog.set(conversation, recent)
      lastActivity.set(conversation, now)
      wake(conversation, 'proactive').catch((error) => log('主动话题失败：', error.message))
    }
  }

  // ---- 启动 ----

  function start() {
    bridge.connect?.()
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
      registeredAgents.clear()
      bridge.close?.()
    })
  }

  return { start, ingest, tick, ensureSession, inbox, sessions, state }
}

/** '23:00-08:00' 这种跨零点区间。 */
export function inQuietHours(now, range) {
  const match = /^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$/.exec(String(range ?? ''))
  if (!match) return false
  const date = new Date(now)
  const minutes = date.getHours() * 60 + date.getMinutes()
  const start = Number(match[1]) * 60 + Number(match[2])
  const end = Number(match[3]) * 60 + Number(match[4])
  return start <= end ? minutes >= start && minutes < end : minutes >= start || minutes < end
}

function createBridgeClient({ url, token, onEvent, log }) {
  let socket = null
  let closed = false
  let retryMs = 1_000
  let reconnectTimer = null
  let seq = 0
  const pending = new Map()

  function connect() {
    if (closed) return
    const target = token ? `${url}${url.includes('?') ? '&' : '?'}access_token=${encodeURIComponent(token)}` : url
    socket = new WebSocket(target)
    socket.addEventListener('open', () => {
      retryMs = 1_000
      log(`已连上桥 ${url}`)
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
      onEvent(data)
    })
    socket.addEventListener('close', () => {
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

  return { connect, call, close: () => { closed = true; clearTimeout(reconnectTimer); socket?.close() } }
}
