// 桥的状态：进程态与连接态是两件事，面板要能区分
// 「进程没起来」和「进程起来了但还没连上」。纯值对象。

export const PROCESSES = ['external', 'stopped', 'starting', 'running', 'failed']
export const CONNECTIONS = ['connecting', 'connected', 'disconnected']

/** external = 桥不在本插件管辖内（用户自己跑的），插件只管连。 */
export function bridgeState(input = {}) {
    return {
        url: String(input.url ?? ''),
        process: PROCESSES.includes(input.process) ? input.process : 'external',
        connection: CONNECTIONS.includes(input.connection) ? input.connection : 'connecting',
        since: Number(input.since) || Date.now(),
        lastError: String(input.lastError ?? ''),
    }
}

export function withConnection(state, connection) {
    if (!CONNECTIONS.includes(connection) || state.connection === connection) return state
    return { ...state, connection, since: Date.now() }
}

export function withProcess(state, process, lastError = '') {
    if (!PROCESSES.includes(process) || state.process === process) return state
    return { ...state, process, since: Date.now(), lastError: process === 'failed' ? String(lastError) : '' }
}
