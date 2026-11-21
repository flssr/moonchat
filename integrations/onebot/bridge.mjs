// MondChat ⇄ OneBot 12 桥：在 agent 账号外面套一层标准协议。
//
// 位置由 docs/truth/backend/messaging.md 定死：OneBot 只在 agent 侧桥接，平台不提供 /onebot。
// 桥不做平台的事：收 Turms 推送（该账号能看到的全部会话），发言走 Biz 唯一写入口。
// 桥也不发明私有动作：只用 OneBot 12 标准动作与事件；未读/游标留给应用侧自己记。
//
// 跑法：
//   cd integrations/onebot && npm install
//   $env:MONDCHAT_ACCOUNT_KEY = '<归属者建 agent 时那串一次性密钥>'
//   node bridge.mjs
//
// 环境变量：
//   MONDCHAT_API_BASE     默认 https://api.mondchat.com
//   MONDCHAT_ACCOUNT_KEY  必填
//   ONEBOT_WS_HOST        默认 127.0.0.1
//   ONEBOT_WS_PORT        默认 6700
//   ONEBOT_ACCESS_TOKEN   可选；设了就必须带 ?access_token= 或 Bearer
//   ONEBOT_HEARTBEAT_MS   默认 15000

import { pathToFileURL } from 'node:url'
import { WebSocketServer } from 'ws'
import TurmsClient from 'turms-client-js'
import {
    PLATFORM,
    buildEvent,
    isAuthorized,
    metaConnectEvent,
    metaHeartbeatEvent,
    segmentsToText,
    splitText,
    toWsUrl,
} from './protocol.mjs'

const IMPL = 'mondchat-onebot'
const IMPL_VERSION = '0.1.0'
const DEVICE_TYPE = 'others'
// Turms 的 DeviceType 是大写枚举；Biz 的 X-Device-Type 是小写，两个都从这里派生。
const TURMS_DEVICE_TYPE = DEVICE_TYPE.toUpperCase()
const ROOMS_TTL_MS = 60_000
const ROOMS_RETRY_MS = 5_000

function fail(retcode, message) {
    return Object.assign(new Error(message), { retcode })
}

export function createBridge() {
    const API_BASE = (process.env.MONDCHAT_API_BASE ?? 'https://api.mondchat.com').replace(/\/+$/, '')
    const ACCOUNT_KEY = process.env.MONDCHAT_ACCOUNT_KEY ?? ''
    const WS_HOST = process.env.ONEBOT_WS_HOST ?? '127.0.0.1'
    const WS_PORT = Number(process.env.ONEBOT_WS_PORT ?? 6700)
    const ACCESS_TOKEN = process.env.ONEBOT_ACCESS_TOKEN ?? ''
    const HEARTBEAT_MS = Number(process.env.ONEBOT_HEARTBEAT_MS ?? 15_000)

    const log = (...args) => console.log('[onebot]', ...args)

    // 长驻进程：漏网的拒绝只该留日志，不该把桥带下去。
    process.on('unhandledRejection', (error) => log('未处理的拒绝：', error?.message ?? error))

    let session = null
    let turms = null
    let refreshTimer = null
    let heartbeatTimer = null
    let stopping = false

    /** Turms group id（字符串）→ 业务 room_id。群推送只有前者。 */
    const roomIdByTurmsGroupId = new Map()
    const roomTitleById = new Map()
    let roomsAt = 0

    const clients = new Set()

    async function request(path, init = {}) {
        const res = await fetch(`${API_BASE}${path}`, {
            ...init,
            signal: init.signal ?? AbortSignal.timeout(20_000),
            headers: {
                'content-type': 'application/json',
                authorization: `Bearer ${ACCOUNT_KEY}`,
                ...(init.headers ?? {}),
            },
        })
        const text = await res.text()
        if (!res.ok) {
            throw fail(1500, `${init.method ?? 'GET'} ${path} → ${res.status} ${text.slice(0, 300)}`)
        }
        return text ? JSON.parse(text) : null
    }

    async function openSession() {
        const res = await fetch(`${API_BASE}/api/sessions`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ account_key: ACCOUNT_KEY }),
            signal: AbortSignal.timeout(20_000),
        })
        const text = await res.text()
        if (!res.ok) throw new Error(`换凭据失败 ${res.status}: ${text.slice(0, 300)}`)
        return JSON.parse(text)
    }

    async function refreshRooms(force = false) {
        // 未映射的群消息可能连续到达：强制刷新也要有节流，别把 Biz 打穿。
        const age = Date.now() - roomsAt
        if (age < ROOMS_RETRY_MS) return
        if (!force && age < ROOMS_TTL_MS) return
        roomsAt = Date.now()
        try {
            const body = await request('/api/rooms')
            for (const room of body?.items ?? []) {
                if (room.turms_group_id == null) continue
                roomIdByTurmsGroupId.set(String(room.turms_group_id), room.room_id)
                roomTitleById.set(room.room_id, room.name)
            }
        } catch (error) {
            // 群列表拿不到不影响私聊，下次推送再试。
            log('读群列表失败：', error.message)
        }
    }

    async function roomIdFor(turmsGroupId) {
        const cached = roomIdByTurmsGroupId.get(turmsGroupId)
        if (cached !== undefined) return cached
        await refreshRooms(true)
        return roomIdByTurmsGroupId.get(turmsGroupId) ?? null
    }

    function broadcast(event) {
        const payload = JSON.stringify(event)
        for (const client of clients) {
            if (client.readyState !== client.OPEN) continue
            try {
                client.send(payload)
            } catch {
                // 连接在检查与发送之间断掉：这次丢掉，别让异常从心跳定时器里冒出去。
                clients.delete(client)
            }
        }
    }

    async function onPush(message) {
        try {
            if (!session) return
            const senderId = String(message.senderId ?? '')
            const text = String(message.text ?? '')
            if (!text || message.isSystemMessage) return
            // 自己的发言也会推回来：应用是通过 action 发的，这里不产生回声事件。
            if (senderId === String(session.turms.user_id)) return

            let roomId = null
            if (message.groupId !== undefined && message.groupId !== null) {
                roomId = await roomIdFor(String(message.groupId))
                if (roomId == null) {
                    log(`收到未映射的群消息：turmsGroupId=${message.groupId}`)
                    return
                }
            }
            broadcast(buildEvent({ selfId: session.account_id, message, roomId }))
        } catch (error) {
            // 这个回调 reject 会以未处理拒绝杀掉长驻进程，整段包住。
            log('处理推送失败：', error.message)
        }
    }

    async function loginTurms(target) {
        const client = new TurmsClient({ wsUrl: toWsUrl(target.turms.gateway_url) })
        await client.userService.login({
            userId: String(target.turms.user_id),
            password: target.turms.credential,
            deviceType: TURMS_DEVICE_TYPE,
        })
        client.messageService.addMessageListener(onPush)
        log(`已连上 /im：账号 ${target.account_id}（${target.display_name}）`)
        return client
    }

    /** 凭据 12 小时过期：到期前重换一次并用新凭据重登（只换局部变量不生效）。 */
    function scheduleRefresh() {
        clearTimeout(refreshTimer)
        const expiresAt = Date.parse(String(session.expires_at ?? ''))
        const delay = Number.isFinite(expiresAt)
            ? Math.max(60_000, expiresAt - Date.now() - 10 * 60_000)
            : 10 * 60_000
        refreshTimer = setTimeout(() => {
            refreshCredential().catch((error) => {
                log('续凭据失败，60 秒后重试：', error.message)
                refreshTimer = setTimeout(() => refreshCredential(), 60_000)
            })
        }, delay)
    }

    async function refreshCredential() {
        const next = await openSession()
        // 先拿新凭据登录成功再换全局状态：登录失败时旧连接还能继续用。
        const client = await loginTurms(next)
        const previous = turms
        session = next
        turms = client
        scheduleRefresh()
        await previous?.close?.()
        log('凭据已续期并重连')
    }

    let watchdogTimer = null
    let disconnectedChecks = 0

    /**
     * turms-client-js 自己会重连，但会话丢了就回不来。连续两次探测失联才重新登录，
     * 免得一次网络抖动就换连接、把在途请求全打掉。
     */
    function startWatchdog() {
        clearInterval(watchdogTimer)
        watchdogTimer = setInterval(() => {
            if (stopping || !turms) return
            let connected = true
            try {
                connected = turms.driver.stateStore().isConnected !== false
            } catch {
                connected = true
            }
            if (connected) {
                disconnectedChecks = 0
                return
            }
            if (++disconnectedChecks < 2) return
            disconnectedChecks = 0
            log('Turms 连接断了，重新登录')
            refreshCredential().catch((error) => log('重新登录失败，60 秒后重试：', error.message))
        }, 30_000)
        watchdogTimer.unref?.()
    }

    async function groupMembers(roomId) {
        const body = await request(`/api/rooms/${roomId}/members`)
        return body?.items ?? []
    }

    function memberView(member) {
        return {
            user_id: String(member.account_id),
            user_name: String(member.display_name ?? ''),
            user_displayname: '',
        }
    }

    async function sendMessage(params) {
        const { text, unsupported } = segmentsToText(params.message)
        if (unsupported) throw fail(1400, `只支持 text 消息段，收到 ${unsupported}`)
        if (!text.trim()) throw fail(1400, '消息内容为空')

        const detailType = params.detail_type
        let conversationType
        let conversationId
        if (detailType === 'private') {
            conversationType = 'dm'
            conversationId = String(params.user_id ?? '')
        } else if (detailType === 'group') {
            conversationType = 'room'
            conversationId = String(params.group_id ?? '')
        } else {
            throw fail(1400, `不支持的 detail_type：${detailType}`)
        }
        if (!conversationId) throw fail(1400, '缺少会话 id')

        // 正文上限 500：长回复切段连发，中途失败则前面的已经发出去了（不做重试，避免重复）。
        let last = null
        for (const chunk of splitText(text)) {
            last = await request(`/api/conversations/${conversationType}/${conversationId}/messages`, {
                method: 'POST',
                headers: { 'x-device-type': DEVICE_TYPE },
                body: JSON.stringify({ text: chunk }),
            })
        }
        const sentAt = Date.parse(String(last?.sent_at ?? ''))
        return {
            message_id: String(last?.message_id ?? ''),
            time: (Number.isFinite(sentAt) ? sentAt : Date.now()) / 1000,
        }
    }

    async function runAction(action, params) {
        switch (action) {
            case 'send_message':
                return sendMessage(params)

            case 'get_self_info':
                return {
                    user_id: String(session.account_id),
                    user_name: session.display_name,
                    user_displayname: session.display_name,
                }

            case 'get_user_info': {
                const userId = String(params.user_id ?? '')
                if (!userId) throw fail(1400, '缺少 user_id')
                const body = await request(`/api/accounts/${userId}`)
                return {
                    user_id: userId,
                    user_name: String(body?.display_name ?? body?.name ?? ''),
                    user_displayname: '',
                    user_remark: '',
                }
            }

            case 'get_friend_list': {
                const body = await request('/api/friendships')
                return (body?.items ?? []).map((item) => ({
                    user_id: String(item.peer_account_id),
                    user_name: String(item.display_name ?? ''),
                    user_displayname: '',
                    user_remark: '',
                }))
            }

            case 'get_group_list':
                await refreshRooms(true)
                return [...roomTitleById.entries()].map(([roomId, name]) => ({
                    group_id: String(roomId),
                    group_name: String(name ?? ''),
                }))

            case 'get_group_info': {
                const roomId = String(params.group_id ?? '')
                if (!roomId) throw fail(1400, '缺少 group_id')
                const body = await request(`/api/rooms/${roomId}`)
                return { group_id: roomId, group_name: String(body?.name ?? '') }
            }

            case 'get_group_member_list': {
                const roomId = String(params.group_id ?? '')
                if (!roomId) throw fail(1400, '缺少 group_id')
                return (await groupMembers(roomId)).map(memberView)
            }

            case 'get_group_member_info': {
                const roomId = String(params.group_id ?? '')
                const userId = String(params.user_id ?? '')
                if (!roomId || !userId) throw fail(1400, '缺少 group_id 或 user_id')
                const member = (await groupMembers(roomId)).find(
                    (item) => String(item.account_id) === userId,
                )
                if (!member) throw fail(1404, `群 ${roomId} 里没有 ${userId}`)
                return memberView(member)
            }

            case 'leave_group': {
                const roomId = String(params.group_id ?? '')
                if (!roomId) throw fail(1400, '缺少 group_id')
                await request(`/api/rooms/${roomId}/members/me`, { method: 'DELETE' })
                return null
            }

            case 'get_version':
                return { impl: IMPL, version: IMPL_VERSION, onebot_version: '12' }

            case 'get_status':
                return {
                    good: true,
                    bots: [{
                        self: { platform: PLATFORM, user_id: String(session.account_id) },
                        online: true,
                    }],
                }

            case 'delete_message':
                throw fail(1404, 'MondChat 不提供撤回')
            case 'set_group_name':
                throw fail(1404, 'MondChat 不提供改群名')
            default:
                throw fail(1404, `不支持的动作：${action}`)
        }
    }

    function authorized(request) {
        return isAuthorized(request, ACCESS_TOKEN)
    }

    function startServer() {
        const server = new WebSocketServer({ host: WS_HOST, port: WS_PORT, maxPayload: 1 << 20 })

        server.on('connection', (socket, request) => {
            if (!authorized(request)) {
                socket.close(1008, 'access token required')
                return
            }
            clients.add(socket)
            socket.on('close', () => clients.delete(socket))
            socket.on('error', (error) => log('连接出错：', error.message))

            // 标准要求：连接建立后的第一个事件必须是 meta.connect。
            socket.send(JSON.stringify(metaConnectEvent({
                selfId: session?.account_id,
                impl: IMPL,
                version: IMPL_VERSION,
            })))
            log(`应用已接入：${clients.size} 个连接`)

            socket.on('message', async (raw) => {
                let request_ = null
                try {
                    request_ = JSON.parse(String(raw))
                } catch {
                    socket.send(JSON.stringify({ status: 'failed', retcode: 1400, data: null, message: '不是合法 JSON' }))
                    return
                }
                const { action, params = {}, echo } = request_
                try {
                    const data = await runAction(action, params)
                    const response = { status: 'ok', retcode: 0, data: data ?? null, message: '' }
                    if (echo !== undefined) response.echo = echo
                    socket.send(JSON.stringify(response))
                } catch (error) {
                    const retcode = error?.retcode ?? 1500
                    if (retcode === 1500) log(`动作 ${action} 失败：`, error.message)
                    const response = { status: 'failed', retcode, data: null, message: error.message }
                    if (echo !== undefined) response.echo = echo
                    socket.send(JSON.stringify(response))
                }
            })
        })

        heartbeatTimer = setInterval(() => {
            broadcast(metaHeartbeatEvent({ selfId: session?.account_id, intervalMs: HEARTBEAT_MS }))
        }, HEARTBEAT_MS)

        log(`OneBot WS 监听 ws://${WS_HOST}:${WS_PORT}${ACCESS_TOKEN ? '（需要 access_token）' : ''}`)
        return server
    }

    async function start() {
        if (!ACCOUNT_KEY) {
            console.error('[onebot] 缺少 MONDCHAT_ACCOUNT_KEY：归属者建 agent 时那串一次性密钥')
            process.exit(2)
        }
        session = await openSession()
        log(`已换到凭据：账号 ${session.account_id}（${session.display_name}）`)
        turms = await loginTurms(session)
        scheduleRefresh()
        startWatchdog()
        await refreshRooms(true)

        const server = startServer()
        const stop = async () => {
            if (stopping) return
            stopping = true
            clearTimeout(refreshTimer)
            clearInterval(heartbeatTimer)
            clearInterval(watchdogTimer)
            for (const client of clients) client.close(1001, 'bridge stopping')
            server.close()
            await turms?.close?.()
            process.exit(0)
        }
        for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, stop)
    }

    return { start }
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
if (isMain) {
    createBridge().start().catch((error) => {
        console.error('[onebot] 启动失败：', error.message)
        process.exit(1)
    })
}
