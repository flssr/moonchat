// 桥里有分支的那几块：直发、群映射、错误码、切段、网关地址、消息段、事件形状。
// 跑法：node selftest.mjs
import assert from 'node:assert/strict'
import {
    buildEvent,
    buildRoomMaps,
    failureView,
    isAuthorized,
    metaConnectEvent,
    metaHeartbeatEvent,
    removeRoom,
    segmentsToText,
    sendText,
    splitText,
    toWsUrl,
} from './protocol.mjs'

// 500 是 Turms max-text-limit 默认值：超了要切，且不能切出空段
assert.deepEqual(splitText('a'.repeat(1001)).map((s) => s.length), [500, 500, 1])
assert.deepEqual(splitText('   '), [], '全空白不产出消息')
assert.deepEqual(splitText('hi'), ['hi'])

// 按 UTF-16 码元切（和 Java String.length 同一口径），但不劈开代理对
const emoji = '🐟'.repeat(600) // 1200 个码元
const parts = splitText(emoji)
assert.equal(parts.length, 3, '1200 码元按 500 切 = 500/500/200')
assert.equal(parts.every((p) => p.length <= 500), true, '每段不超过 500 个 UTF-16 码元')
assert.equal(parts.join(''), emoji, '拼回去必须一字不差，说明没劈开代理对')
assert.equal(parts.every((p) => Array.from(p).every((c) => c === '🐟')), true)

// 群映射双向使用业务 room_id 与 Turms group id，刷新和退群都不留旧映射
const roomMaps = buildRoomMaps([
    { room_id: 7, turms_group_id: '42', name: '测试群' },
    { room_id: 8, turms_group_id: null, name: '未投影' },
])
assert.equal(roomMaps.roomIdByTurmsGroupId.get('42'), '7')
assert.equal(roomMaps.turmsGroupIdByRoomId.get('7'), '42')
assert.equal(roomMaps.roomTitleById.get('7'), '测试群')
assert.equal(roomMaps.roomTitleById.has('8'), false)
const refreshedRooms = buildRoomMaps([{ room_id: 9, turms_group_id: '43', name: '新群' }])
assert.equal(refreshedRooms.roomIdByTurmsGroupId.has('42'), false, '整体重建后不留旧群')
assert.equal(refreshedRooms.turmsGroupIdByRoomId.has('7'), false)
removeRoom(roomMaps, 7)
assert.equal(roomMaps.roomIdByTurmsGroupId.has('42'), false, '退群后反查映射也删掉')
assert.equal(roomMaps.turmsGroupIdByRoomId.has('7'), false)
assert.equal(roomMaps.roomTitleById.has('7'), false)

// 直发只调用已登录账号的 messageService；私聊 targetId 是对端账号 id
const requests = []
let sequence = 0
const messageService = {
    async sendMessage(request) {
        requests.push(request)
        sequence += 1
        return {
            data: String(18_824_821_687_755_735_000n + BigInt(sequence)),
            timestamp: new Date(Date.UTC(2026, 10, 25, 15, 30, sequence)),
        }
    },
}
const privateResult = await sendText(messageService, {
    isGroupMessage: false,
    targetId: '100000004',
    text: '在吗',
})
assert.deepEqual(requests[0], { isGroupMessage: false, targetId: '100000004', text: '在吗' })
assert.equal(privateResult.message_id, '18824821687755735001')
assert.equal(typeof privateResult.message_id, 'string', '超过 2^53 的 Turms 消息 id 不丢精度')
assert.equal(privateResult.time, Date.UTC(2026, 10, 25, 15, 30, 1) / 1000, 'time 取 Response.timestamp')

// 群聊把 OneBot 的 room_id 反查成 turms_group_id；长文切段并取最后一段响应
requests.length = 0
const groupResult = await sendText(messageService, {
    isGroupMessage: true,
    targetId: refreshedRooms.turmsGroupIdByRoomId.get('9'),
    text: 'a'.repeat(1001),
})
assert.equal(requests.length, 3)
assert.deepEqual(requests.map((request) => request.text.length), [500, 500, 1])
assert.ok(requests.every((request) => request.isGroupMessage && request.targetId === '43'))
assert.equal(groupResult.message_id, '18824821687755735004')
assert.equal(groupResult.time, Date.UTC(2026, 10, 25, 15, 30, 4) / 1000)

// Turms ResponseError 的 code/reason 不塌成 1500
for (const code of [1101, 5001, 1106]) {
    assert.deepEqual(failureView({ code, reason: `turms-${code}` }), {
        retcode: code,
        message: `turms-${code}`,
    })
}
assert.deepEqual(failureView(Object.assign(new Error('只支持 text'), { retcode: 1400 })), {
    retcode: 1400,
    message: '只支持 text',
})
assert.deepEqual(failureView(new Error('unknown')), { retcode: 1500, message: 'unknown' })

// 网关地址三种写法都归一成 ws(s)://
assert.equal(toWsUrl('wss://api.mondchat.com/im'), 'wss://api.mondchat.com/im')
assert.equal(toWsUrl('https://api.mondchat.com/im'), 'wss://api.mondchat.com/im')
assert.equal(toWsUrl('http://localhost:20510'), 'ws://localhost:20510')
assert.equal(toWsUrl('localhost:20510'), 'ws://localhost:20510')

// 只收 text 段；其他段必须显式报错，不能静默丢
assert.deepEqual(segmentsToText([{ type: 'text', data: { text: '你好' } }]), { text: '你好', unsupported: null })
assert.deepEqual(segmentsToText('纯字符串'), { text: '纯字符串', unsupported: null })
assert.equal(segmentsToText([{ type: 'image', data: { file_id: 'x' } }]).unsupported, 'image')
assert.equal(segmentsToText([{ type: 'text', data: { text: 'a' } }, { type: 'image', data: {} }]).unsupported, 'image')

// 事件形状：id 是字符串、群消息用业务 room_id、时间戳是秒
const groupEvent = buildEvent({
    selfId: 100000001,
    roomId: 7,
    message: { id: '1800000000000000001', senderId: '100000002', text: 'hi', groupId: '42', deliveryDate: '2026-11-21T12:00:00Z' },
})
assert.equal(groupEvent.type, 'message')
assert.equal(groupEvent.detail_type, 'group')
assert.equal(groupEvent.message_id, '1800000000000000001')
assert.equal(groupEvent.group_id, '7', '群事件用 room_id，不是 turms group id')
assert.equal(groupEvent.user_id, '100000002')
assert.equal(groupEvent.self.user_id, '100000001')
assert.equal(groupEvent.time, Date.parse('2026-11-21T12:00:00Z') / 1000)
assert.equal(typeof groupEvent.message_id, 'string', '消息 id 超过 2^53，必须是字符串')

const privateEvent = buildEvent({ selfId: 1, roomId: null, message: { id: '2', senderId: '3', text: 'yo' } })
assert.equal(privateEvent.detail_type, 'private')
assert.ok(!('group_id' in privateEvent), '私聊事件不带 group_id')

// 元事件：connect 必须是连接后的第一个事件，心跳带 interval
const connect = metaConnectEvent({ selfId: 1, impl: 'mondchat-onebot', version: '0.1.0' })
assert.equal(connect.type, 'meta')
assert.equal(connect.detail_type, 'connect')
assert.deepEqual(connect.version, { impl: 'mondchat-onebot', version: '0.1.0', onebot_version: '12' })

const beat = metaHeartbeatEvent({ selfId: 1, intervalMs: 15000 })
assert.equal(beat.type, 'meta')
assert.equal(beat.detail_type, 'heartbeat')
assert.equal(beat.interval, 15000)

// 桥只绑回环，但被转发出去时 access_token 是唯一一道门
const req = (url, headers = {}) => ({ url, headers })
assert.equal(isAuthorized(req('/'), ''), true, '没配 token 就等同不设防')
assert.equal(isAuthorized(req('/?access_token=t'), 't'), true)
assert.equal(isAuthorized(req('/'), 't'), false, '不带 token 要被挡')
assert.equal(isAuthorized(req('/?access_token=nope'), 't'), false, '错 token 要被挡')
assert.equal(isAuthorized(req('/?foo=1&access_token=t'), 't'), true, '其它查询参数不影响')
assert.equal(isAuthorized(req('/', { authorization: 'Bearer t' }), 't'), true)
assert.equal(isAuthorized(req('/', { authorization: 'Bearer other' }), 't'), false)

console.log('[onebot] selftest ok')