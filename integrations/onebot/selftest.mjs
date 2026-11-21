// 桥里唯一有分支的那几块：切段、网关地址、消息段、事件形状。跑法：node selftest.mjs
import assert from 'node:assert/strict'
import { buildEvent, metaConnectEvent, metaHeartbeatEvent, segmentsToText, splitText, toWsUrl } from './protocol.mjs'

// 500 字上限：超了要切，且不能切出空段
assert.deepEqual(splitText('a'.repeat(1001)).map((s) => s.length), [500, 500, 1])
assert.deepEqual(splitText('   '), [], '全空白不产出消息')
assert.deepEqual(splitText('hi'), ['hi'])

// 按 UTF-16 码元切（和 Biz 的 @Size 同一口径），但不劈开代理对
const emoji = '🐟'.repeat(600) // 1200 个码元
const parts = splitText(emoji)
assert.equal(parts.length, 3, '1200 码元按 500 切 = 500/500/200')
assert.equal(parts.every((p) => p.length <= 500), true, '每段不超过 500 个 UTF-16 码元')
assert.equal(parts.join(''), emoji, '拼回去必须一字不差，说明没劈开代理对')
assert.equal(parts.every((p) => Array.from(p).every((c) => c === '🐟')), true)

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

console.log('[onebot] selftest ok')