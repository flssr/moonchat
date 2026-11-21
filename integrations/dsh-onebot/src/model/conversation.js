// 会话标识的值对象：`private:100000004` / `group:2`。
// 纯函数，不碰宿主，可以被 selftest 直接断言。

export const PRIVATE = 'private'
export const GROUP = 'group'

/** 组一个会话 key；kind 不合法就抛，别让脏值流进映射表。 */
export function conversationKey(kind, id) {
    if (kind !== PRIVATE && kind !== GROUP) throw new Error(`未知会话类型：${kind}`)
    const value = String(id ?? '').trim()
    if (!/^\d+$/.test(value)) throw new Error(`会话 id 必须是数字：${id}`)
    return `${kind}:${value}`
}

/** 拆会话 key；不是我们认识的形状就返回 null，调用方自己决定丢还是报错。 */
export function parseConversation(key) {
    const match = /^(private|group):(\d+)$/.exec(String(key ?? ''))
    if (!match) return null
    return { kind: match[1], id: match[2] }
}

export function isGroup(key) {
    return parseConversation(key)?.kind === GROUP
}

/** 「群「测试群聊」(2)」或「与「flssr」(100000004) 的私聊」；没名字就退回 id。 */
export function describe(key, name = '') {
    const parsed = parseConversation(key)
    if (!parsed) return String(key ?? '')
    const label = name ? `「${name}」(${parsed.id})` : parsed.id
    return parsed.kind === GROUP ? `群${label}` : `与${label}的私聊`
}

/** DSH 会话标题：侧栏里认得出是哪个 MondChat 会话。 */
export function titleOf(key, name = '') {
    const parsed = parseConversation(key)
    if (!parsed) return `MondChat · ${key}`
    const label = name ? ` ${name}` : ` ${parsed.id}`
    return parsed.kind === GROUP ? `MondChat · 群${label}` : `MondChat · 与${label} 的私聊`
}
