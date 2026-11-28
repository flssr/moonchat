// 短期层：每个会话一段滚动摘要。只压「更早的那一段」，最近的消息仍由原话层保留。
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const SUMMARY_LIMIT = 600

function empty() {
    return {}
}

export function createShortStore({ file }) {
    if (!file) throw new Error('短期记忆文件路径不能为空')
    mkdirSync(dirname(file), { recursive: true })
    let cache = null

    function load() {
        if (cache) return cache
        try {
            const parsed = JSON.parse(readFileSync(file, 'utf8'))
            cache = parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : empty()
        } catch {
            cache = empty()
        }
        return cache
    }

    function save(next) {
        cache = next
        const temp = `${file}.tmp`
        writeFileSync(temp, JSON.stringify(next, null, 2))
        renameSync(temp, file)
    }

    function get(conversation) {
        const value = load()[String(conversation ?? '')]
        return value && typeof value.summary === 'string' ? value : null
    }

    function set(conversation, { summary, throughId = '', throughAt = 0 }) {
        const key = String(conversation ?? '')
        const text = String(summary ?? '').trim().slice(0, SUMMARY_LIMIT)
        if (!key || !text) return null
        const next = { ...load() }
        const entry = {
            summary: text,
            throughId: String(throughId ?? ''),
            throughAt: Number(throughAt) || 0,
            updatedAt: Date.now(),
        }
        next[key] = entry
        save(next)
        return entry
    }

    return { file, get, set, all: load }
}
