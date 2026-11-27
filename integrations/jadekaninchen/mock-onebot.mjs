// 简易 OneBot 12 mock 服务端：没有 IM/Turms 时，用它冒充 integrations/onebot 的 6700。
// 只实现插件用到的动作与事件；不连 Turms、不写数据库、不做协议之外的事。
//
// 跑法：
//   node mock-onebot.mjs
//   p 你好        # 发一条私聊事件
//   g 大家好      # 发一条群事件
//   q             # 退出
import { createHash, randomUUID } from 'node:crypto'
import http from 'node:http'
import { pathToFileURL } from 'node:url'
import readline from 'node:readline'

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const PLATFORM = 'mondchat'

function encodeFrame(opcode, payload) {
    const data = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload))
    let header
    if (data.length < 126) {
        header = Buffer.from([0x80 | opcode, data.length])
    } else if (data.length < 65_536) {
        header = Buffer.alloc(4)
        header[0] = 0x80 | opcode
        header[1] = 126
        header.writeUInt16BE(data.length, 2)
    } else {
        header = Buffer.alloc(10)
        header[0] = 0x80 | opcode
        header[1] = 127
        header.writeBigUInt64BE(BigInt(data.length), 2)
    }
    return Buffer.concat([header, data])
}

function closeFrame(code = 1000, reason = '') {
    const body = Buffer.alloc(2 + Buffer.byteLength(reason))
    body.writeUInt16BE(code, 0)
    body.write(reason, 2)
    return encodeFrame(0x8, body)
}

function sendJson(client, value) {
    if (client.socket.destroyed) return
    client.socket.write(encodeFrame(0x1, JSON.stringify(value)))
}

function metaConnect(selfId) {
    return {
        id: randomUUID(),
        self: { platform: PLATFORM, user_id: selfId },
        time: Date.now() / 1000,
        type: 'meta',
        detail_type: 'connect',
        sub_type: '',
        version: { impl: 'jadekaninchen-mock', version: '0.1.0', onebot_version: '12' },
    }
}

function metaHeartbeat(selfId, intervalMs) {
    return {
        id: randomUUID(),
        self: { platform: PLATFORM, user_id: selfId },
        time: Date.now() / 1000,
        type: 'meta',
        detail_type: 'heartbeat',
        sub_type: '',
        interval: intervalMs,
    }
}

function messageEvent({ selfId, detailType, text, userId, groupId }) {
    const event = {
        id: randomUUID(),
        self: { platform: PLATFORM, user_id: selfId },
        time: Date.now() / 1000,
        type: 'message',
        detail_type: detailType,
        sub_type: '',
        message_id: String(Date.now()),
        message: [{ type: 'text', data: { text } }],
        alt_message: text,
        user_id: String(userId),
    }
    if (detailType === 'group') event.group_id = String(groupId)
    return event
}

function actionData(action, params, { selfId, peerId, groupId }) {
    switch (action) {
        case 'get_self_info':
            return { user_id: selfId, user_name: 'Jadekaninchen', user_displayname: 'Jadekaninchen' }
        case 'get_user_info':
            return {
                user_id: String(params?.user_id ?? peerId),
                user_name: '测试用户',
                user_displayname: '',
                user_remark: '',
            }
        case 'get_friend_list':
            return [{ user_id: peerId, user_name: '测试用户', user_displayname: '', user_remark: '' }]
        case 'get_group_list':
            return [{ group_id: groupId, group_name: '测试群' }]
        case 'get_group_info':
            return { group_id: String(params?.group_id ?? groupId), group_name: '测试群' }
        case 'get_group_member_list':
            return [
                { user_id: selfId, user_name: 'Jadekaninchen', user_displayname: '' },
                { user_id: peerId, user_name: '测试用户', user_displayname: '' },
            ]
        case 'get_group_member_info':
            return {
                user_id: String(params?.user_id ?? peerId),
                user_name: '测试用户',
                user_displayname: '',
            }
        case 'send_message':
            return { message_id: String(Date.now()), time: Date.now() / 1000 }
        case 'get_version':
            return { impl: 'jadekaninchen-mock', version: '0.1.0', onebot_version: '12' }
        case 'get_status':
            return { good: true, bots: [{ self: { platform: PLATFORM, user_id: selfId }, online: true }] }
        default:
            return null
    }
}

/** 起一个只支持文本帧的最小 WebSocket 服务；返回端口与发事件的方法。 */
export async function createMockServer({
    host = '127.0.0.1',
    port = 6700,
    selfId = '100000001',
    peerId = '100000002',
    groupId = '1',
    intervalMs = 0,
    log = () => {},
} = {}) {
    const clients = new Set()
    const server = http.createServer((_request, response) => {
        response.writeHead(404)
        response.end('mock-onebot: websocket only\n')
    })

    function broadcast(event) {
        for (const client of clients) sendJson(client, event)
    }

    function emitMessage({ text = '测试消息', detailType = 'private', userId = peerId, group = groupId } = {}) {
        const event = messageEvent({ selfId, detailType, text, userId, groupId: group })
        broadcast(event)
        log(`→ ${detailType} ${text}`)
        return event
    }

    function handleAction(client, raw) {
        let request
        try {
            request = JSON.parse(raw)
        } catch {
            sendJson(client, { status: 'failed', retcode: 1400, data: null, message: '不是合法 JSON' })
            return
        }
        const { action, params = {}, echo } = request
        const data = actionData(action, params, { selfId, peerId, groupId })
        log(`← ${action}`)
        sendJson(client, {
            status: 'ok',
            retcode: 0,
            data,
            message: '',
            ...(echo !== undefined ? { echo } : {}),
        })
    }

    function handleFrame(client, opcode, payload) {
        if (opcode === 0x1) {
            handleAction(client, payload.toString('utf8'))
            return
        }
        if (opcode === 0x8) {
            client.socket.write(closeFrame(1000, 'bye'))
            client.socket.end()
            return
        }
        if (opcode === 0x9) {
            client.socket.write(encodeFrame(0xa, payload))
        }
    }

    function consume(client) {
        while (true) {
            const buffer = client.buffer
            if (buffer.length < 2) return
            const first = buffer[0]
            const second = buffer[1]
            const fin = (first & 0x80) !== 0
            const opcode = first & 0x0f
            const masked = (second & 0x80) !== 0
            let length = second & 0x7f
            let offset = 2
            if (length === 126) {
                if (buffer.length < 4) return
                length = buffer.readUInt16BE(2)
                offset = 4
            } else if (length === 127) {
                if (buffer.length < 10) return
                const big = buffer.readBigUInt64BE(2)
                if (big > BigInt(Number.MAX_SAFE_INTEGER)) {
                    client.socket.destroy()
                    return
                }
                length = Number(big)
                offset = 10
            }
            if (!masked) {
                // 浏览器/Node 客户端必须带 mask；不带就是坏帧，直接断。
                client.socket.destroy()
                return
            }
            if (buffer.length < offset + 4 + length) return
            const mask = buffer.subarray(offset, offset + 4)
            offset += 4
            const payload = Buffer.from(buffer.subarray(offset, offset + length))
            for (let i = 0; i < payload.length; i += 1) payload[i] ^= mask[i % 4]
            client.buffer = buffer.subarray(offset + length)

            if (!fin) {
                // 只做最小分片拼接；插件发的 JSON 很小，正常不会走到这里。
                if (opcode !== 0) client.fragments = { opcode, chunks: [payload] }
                else client.fragments?.chunks.push(payload)
                continue
            }
            if (opcode === 0 && client.fragments) {
                client.fragments.chunks.push(payload)
                const joined = Buffer.concat(client.fragments.chunks)
                const original = client.fragments.opcode
                client.fragments = null
                handleFrame(client, original, joined)
            } else {
                handleFrame(client, opcode, payload)
            }
        }
    }

    server.on('upgrade', (request, socket) => {
        const key = request.headers['sec-websocket-key']
        if (!key) {
            socket.destroy()
            return
        }
        const accept = createHash('sha1').update(key + WS_GUID).digest('base64')
        socket.write([
            'HTTP/1.1 101 Switching Protocols',
            'Upgrade: websocket',
            'Connection: Upgrade',
            `Sec-WebSocket-Accept: ${accept}`,
            '', '',
        ].join('\r\n'))
        socket.setNoDelay(true)

        const client = { socket, buffer: Buffer.alloc(0), fragments: null }
        clients.add(client)
        socket.on('data', (chunk) => {
            client.buffer = Buffer.concat([client.buffer, chunk])
            consume(client)
        })
        socket.on('close', () => clients.delete(client))
        socket.on('error', () => clients.delete(client))
        sendJson(client, metaConnect(selfId))
        log(`客户端已连接：${clients.size}`)
    })

    const heartbeat = setInterval(() => {
        broadcast(metaHeartbeat(selfId, 15_000))
    }, 15_000)
    heartbeat.unref?.()

    const auto = intervalMs > 0
        ? setInterval(() => emitMessage({ text: `自动消息 ${new Date().toLocaleTimeString()}` }), intervalMs)
        : null
    auto?.unref?.()

    await new Promise((resolve, reject) => {
        server.once('error', reject)
        server.listen(port, host, () => {
            server.off('error', reject)
            resolve()
        })
    })

    const actualPort = server.address().port
    log(`mock OneBot 监听 ws://${host}:${actualPort}`)

    return {
        server,
        host,
        port: actualPort,
        emitMessage,
        close: async () => {
            clearInterval(heartbeat)
            if (auto) clearInterval(auto)
            for (const client of clients) {
                client.socket.write(closeFrame(1001, 'mock stopping'))
                client.socket.end()
            }
            clients.clear()
            await new Promise((resolve) => server.close(resolve))
        },
    }
}

function parseArgs(argv) {
    const options = {}
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i]
        if (!arg.startsWith('--')) continue
        const name = arg.slice(2)
        const value = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true'
        options[name] = value
    }
    return options
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
if (isMain) {
    const args = parseArgs(process.argv.slice(2))
    const mock = await createMockServer({
        host: args.host ?? '127.0.0.1',
        port: Number(args.port ?? 6700),
        selfId: String(args.self ?? '100000001'),
        peerId: String(args.peer ?? '100000002'),
        groupId: String(args.group ?? '1'),
        intervalMs: Number(args.interval ?? 0),
        log: (...parts) => console.log('[mock-onebot]', ...parts),
    })
    console.log('[mock-onebot] 命令：p <文本> 私聊，g <文本> 群聊，q 退出')
    if (args.text) {
        setTimeout(() => mock.emitMessage({ text: String(args.text) }), 500).unref?.()
    }
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
    rl.on('line', async (line) => {
        const text = line.trim()
        if (!text) return
        if (text === 'q' || text === 'quit') {
            rl.close()
            await mock.close()
            process.exit(0)
        }
        if (text === 'h' || text === 'help') {
            console.log('p <文本> 私聊，g <文本> 群聊，q 退出')
            return
        }
        if (text.startsWith('g ')) {
            mock.emitMessage({ text: text.slice(2), detailType: 'group' })
            return
        }
        mock.emitMessage({ text: text.startsWith('p ') ? text.slice(2) : text })
    })
}
