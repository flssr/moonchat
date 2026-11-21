// 工具注册：只决定把哪些工具挂到哪个 agent 上，工具本体在 ./tools/ 下各自一个文件。
import { createSendTool, NAME as SEND } from './tools/send.js'
import { createUnreadTool, NAME as UNREAD } from './tools/unread.js'

export const TOOL_UNREAD = UNREAD
export const TOOL_SEND = SEND

/** 把工具挂到某个 agent 的上下文里；返回 disposer 列表（agent 不能注册时返回空）。 */
export function registerTools(agent, key, service) {
    const tools = agent?.ctx?.tools
    if (typeof tools?.register !== 'function') return []
    return [
        tools.register(createUnreadTool(key, service)),
        tools.register(createSendTool(key, service)),
    ]
}
