// 原话层：一个 JSONL 文件，追加写、按会话读。
// 不在这里做摘要或模型调用；短期摘要和长期事实分别在 short.js / core.js。
import { randomUUID } from 'node:crypto'
import { appendFileSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
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
        id: String(record?.id ?? ''),
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

    // ponytail: 单文件只追加，按保留期轮转；记录量再大就换 SQLite。
    function append(record) {
        const entry = normalize({ ...record, id: record?.id || randomUUID() })
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

    function list(conversation) {
        const key = String(conversation ?? '')
        return key ? readAll().filter((entry) => entry.conversation === key) : []
    }

    function recent(conversation, limit = 20) {
        return list(conversation).slice(-normalizeLimit(limit))
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

    /** 按保留期清理原话；摘要不依赖原话还在，所以删旧记录是安全的。 */
    function prune(days = 30, now = Date.now()) {
        const cutoff = now - Math.max(1, Number(days) || 30) * 86400_000
        const entries = readAll()
        const kept = entries.filter((entry) => entry.at >= cutoff)
        if (kept.length === entries.length) return 0
        const temp = `${file}.tmp`
        writeFileSync(temp, kept.map((entry) => `${JSON.stringify(entry)}\n`).join(''))
        renameSync(temp, file)
        return entries.length - kept.length
    }

    function stats() {
        const entries = readAll()
        return {
            records: entries.length,
            conversations: new Set(entries.map((entry) => entry.conversation)).size,
        }
    }

    return { file, append, list, recent, search, prune, stats }
}
