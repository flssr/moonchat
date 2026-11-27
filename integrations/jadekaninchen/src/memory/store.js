// 会话记忆：一个 JSONL 文件，追加写、按会话读。
// 只存消息事实（谁、什么时候、说了什么、方向），不做摘要也不调模型；检索是大小写不敏感的子串。
import { appendFileSync, mkdirSync, readFileSync } from 'node:fs'
import { dirname } from 'node:path'

const TEXT_LIMIT = 2_000
const MAX_LIMIT = 50

function normalizeLimit(value) {
    const parsed = Number(value)
    if (!Number.isFinite(parsed)) return 20
    return Math.max(1, Math.min(MAX_LIMIT, Math.trunc(parsed)))
}

function normalize(record) {
    const conversation = String(record?.conversation ?? '')
    const text = String(record?.text ?? '').slice(0, TEXT_LIMIT)
    if (!conversation || !text.trim()) return null
    const at = Number(record?.at)
    return {
        at: Number.isFinite(at) && at > 0 ? at : Date.now(),
        conversation,
        direction: record?.direction === 'out' ? 'out' : 'in',
        userId: String(record?.userId ?? ''),
        text,
        messageId: String(record?.messageId ?? ''),
    }
}

export function createMemoryStore({ file }) {
    if (!file) throw new Error('记忆文件路径不能为空')
    mkdirSync(dirname(file), { recursive: true })

    // ponytail: 单文件只追加、不压缩；记录量上来后按大小轮转或换成 SQLite。
    function append(record) {
        const entry = normalize(record)
        if (!entry) return null
        appendFileSync(file, `${JSON.stringify(entry)}\n`)
        return entry
    }

    function readAll() {
        let raw = ''
        try {
            raw = readFileSync(file, 'utf8')
        } catch {
            return []
        }
        const entries = []
        for (const line of raw.split('\n')) {
            if (!line.trim()) continue
            try {
                const entry = normalize(JSON.parse(line))
                if (entry) entries.push(entry)
            } catch {
                // 半行或手改坏的行跳过：记忆坏了不该把插件带下去。
            }
        }
        return entries
    }

    function recent(conversation, limit = 20) {
        const key = String(conversation ?? '')
        if (!key) return []
        return readAll()
            .filter((entry) => entry.conversation === key)
            .slice(-normalizeLimit(limit))
    }

    function search(query, { conversation = '', limit = 20 } = {}) {
        const needle = String(query ?? '').trim().toLowerCase()
        if (!needle) return []
        const key = String(conversation ?? '')
        return readAll()
            .filter((entry) => (!key || entry.conversation === key)
                && entry.text.toLowerCase().includes(needle))
            .slice(-normalizeLimit(limit))
    }

    function stats() {
        const entries = readAll()
        return {
            records: entries.length,
            conversations: new Set(entries.map((entry) => entry.conversation)).size,
        }
    }

    return { file, append, recent, search, stats }
}
