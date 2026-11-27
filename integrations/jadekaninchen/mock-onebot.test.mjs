// mock-onebot 的冒烟：真实 WS 握手、meta.connect、action echo、消息广播。
// 跑法：node mock-onebot.test.mjs
import assert from 'node:assert/strict'
import { createMockServer } from './mock-onebot.mjs'

const waitFor = async (predicate, label, timeoutMs = 3_000) => {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
        if (predicate()) return
        await new Promise((resolve) => setTimeout(resolve, 20))
    }
    throw new Error(`等待超时：${label}`)
}

const mock = await createMockServer({ port: 0, log: () => {} })
const socket = new WebSocket(`ws://127.0.0.1:${mock.port}`)
const received = []
socket.addEventListener('message', (event) => {
    try {
        received.push(JSON.parse(String(event.data)))
    } catch {
        // 测试只发 JSON，解析失败就是 bug；让下面的断言暴露。
    }
})

await waitFor(() => received.some((event) => event.type === 'meta' && event.detail_type === 'connect'), 'meta.connect')
assert.equal(received[0].detail_type, 'connect', '连接后的第一个事件必须是 meta.connect')

socket.send(JSON.stringify({ action: 'get_version', params: {}, echo: 'e1' }))
await waitFor(() => received.some((event) => event.echo === 'e1'), 'get_version echo')
const version = received.find((event) => event.echo === 'e1')
assert.equal(version.status, 'ok')
assert.equal(version.data.onebot_version, '12')

socket.send(JSON.stringify({ action: 'send_message', params: { detail_type: 'private' }, echo: 'e2' }))
await waitFor(() => received.some((event) => event.echo === 'e2'), 'send_message echo')
const sent = received.find((event) => event.echo === 'e2')
assert.equal(sent.status, 'ok')
assert.equal(typeof sent.data.message_id, 'string')

mock.emitMessage({ text: '记忆测试', detailType: 'group', userId: '100000009' })
await waitFor(() => received.some((event) => event.type === 'message' && event.alt_message === '记忆测试'), '群消息')
const message = received.find((event) => event.alt_message === '记忆测试')
assert.equal(message.detail_type, 'group')
assert.equal(message.group_id, '1')
assert.equal(message.user_id, '100000009')

socket.close()
await waitFor(() => socket.readyState === WebSocket.CLOSED, '客户端关闭')
await mock.close()
console.log('[jadekaninchen] mock-onebot ok')
