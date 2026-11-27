// 桥客户端：只管 OneBot 12 的会话、echo 与退避，不碰 MondChat 的业务。
export function createBridgeClient({ url, token, onEvent, onStatus, log }) {
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
            onStatus('disconnected')
            if (closed) return
            reconnectTimer = setTimeout(connect, retryMs)
            reconnectTimer.unref?.()
            retryMs = Math.min(retryMs * 2, 30_000)
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
        close: () => {
            closed = true
            clearTimeout(reconnectTimer)
            socket?.close()
        },
    }
}
