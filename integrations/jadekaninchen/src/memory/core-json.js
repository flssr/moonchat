// 长期层：结构化事实 + 本地 BM25 检索。
// 事实先合并/标过时，不直接删；检索按内容相关度、重要度和新近程度排序。
import { randomUUID } from 'node:crypto'
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const TEXT_LIMIT = 400
const MAX_FACTS_PER_CONVERSATION = 300
const STOP = new Set('的了是我你他她它们在有和就不也都很吗吧呢啊呀哦嗯这那个一上下来去说要会能着过'.split(''))

const empty = () => ({ facts: [] })

function clip(value, limit = TEXT_LIMIT) {
    return [...String(value ?? '').trim()].slice(0, limit).join('')
}

/** 中文二元字组 + 英文/数字整词；单字段去掉停用字。 */
export function tokenize(text) {
    const out = []
    for (const match of String(text ?? '').toLowerCase().matchAll(/[a-z0-9_]{2,}|[一-鿿]+/g)) {
        const word = match[0]
        if (/^[a-z0-9_]+$/.test(word)) {
            out.push(word)
            continue
        }
        if (word.length === 1) {
            if (!STOP.has(word)) out.push(word)
            continue
        }
        for (let i = 0; i < word.length - 1; i += 1) out.push(word.slice(i, i + 2))
    }
    return out
}

export function similarity(a, b) {
    const A = new Set(tokenize(a))
    const B = new Set(tokenize(b))
    if (!A.size || !B.size) return 0
    let shared = 0
    for (const token of A) if (B.has(token)) shared += 1
    return shared / (A.size + B.size - shared)
}

/** 字面很像但语义冲突：否定词数量不同，或数字不同。 */
export function conflicting(a, b) {
    const count = (text) => (String(text).match(/[不没未别无非]/g) || []).length
    if (count(a) !== count(b)) return true
    const numbers = (text) => (String(text).match(/\d+/g) || []).join(',')
    const x = numbers(a)
    const y = numbers(b)
    return Boolean(x && y && x !== y)
}

export function normalizeFact(fact) {
    const conversation = String(fact?.conversation ?? '')
    const text = clip(fact?.text)
    if (!conversation || !text) return null
    const at = Number(fact?.at)
    const importance = Number(fact?.importance)
    return {
        id: String(fact?.id ?? '') || randomUUID(),
        text,
        conversation,
        subject: String(fact?.subject ?? ''),
        subjectName: clip(fact?.subjectName, 40),
        at: Number.isFinite(at) && at > 0 ? at : Date.now(),
        createdAt: Number(fact?.createdAt) || Date.now(),
        updatedAt: Number(fact?.updatedAt) || Date.now(),
        importance: Number.isFinite(importance) ? Math.max(0, Math.min(1, importance)) : 0.5,
        source: String(fact?.source ?? 'extract'),
        status: fact?.status === 'stale' ? 'stale' : 'active',
        validUntil: Number(fact?.validUntil) || 0,
    }
}

/** 会话隔离：事实只在被提炼出来的那个会话可见，不跨私聊、也不进群。 */
function visible(fact, conversation) {
    return fact.status === 'active' && fact.conversation === conversation
}

function buildIndex(facts) {
    const df = new Map()
    const docs = facts.map((fact) => {
        const tokens = tokenize(`${fact.text} ${fact.subjectName}`)
        const tf = new Map()
        for (const token of tokens) tf.set(token, (tf.get(token) || 0) + 1)
        for (const token of tf.keys()) df.set(token, (df.get(token) || 0) + 1)
        return { fact, tf, len: tokens.length || 1 }
    })
    const avgLen = docs.reduce((sum, doc) => sum + doc.len, 0) / (docs.length || 1)
    return { docs, df, avgLen, total: docs.length }
}

export function createJsonCoreStore({ file }) {
    if (!file) throw new Error('长期记忆文件路径不能为空')
    mkdirSync(dirname(file), { recursive: true })
    let cache = null

    function load() {
        if (cache) return cache
        try {
            const parsed = JSON.parse(readFileSync(file, 'utf8'))
            const facts = Array.isArray(parsed?.facts) ? parsed.facts.map(normalizeFact).filter(Boolean) : []
            cache = { facts }
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

    function add(fact) {
        const entry = normalizeFact({ ...fact, id: fact?.id || randomUUID() })
        if (!entry) return null
        const state = load()
        const facts = [...state.facts]
        const old = facts.find((item) => item.status === 'active'
            && item.conversation === entry.conversation
            && item.subject === entry.subject
            && similarity(item.text, entry.text) >= 0.6)
        if (old && !conflicting(old.text, entry.text)) {
            old.text = entry.text.length > old.text.length ? entry.text : old.text
            old.importance = Math.max(old.importance, entry.importance)
            old.at = Math.max(old.at, entry.at)
            old.updatedAt = Date.now()
            old.source = entry.source
            save({ facts })
            return old
        }
        if (old) {
            old.status = 'stale'
            old.validUntil = entry.at
            old.updatedAt = Date.now()
        }
        facts.push(entry)
        // 每会话封顶：优先丢最旧的已过时事实，其次丢重要度最低的旧事实。
        const own = facts.filter((item) => item.conversation === entry.conversation)
        if (own.length > MAX_FACTS_PER_CONVERSATION) {
            const drop = own
                .sort((a, b) => Number(b.status === 'stale') - Number(a.status === 'stale')
                    || a.importance - b.importance
                    || a.at - b.at)
                .slice(0, own.length - MAX_FACTS_PER_CONVERSATION)
            const remove = new Set(drop.map((item) => item.id))
            save({ facts: facts.filter((item) => !remove.has(item.id)) })
            return entry
        }
        save({ facts })
        return entry
    }

    function search(query, { conversation, limit = 6 } = {}) {
        const key = String(conversation ?? '')
        const facts = load().facts.filter((fact) => visible(fact, key))
        if (facts.length === 0) return []
        const tokens = [...new Set(tokenize(query))]
        if (tokens.length === 0) return recent(key, limit)
        const index = buildIndex(facts)
        const k1 = 1.4
        const b = 0.7
        const now = Date.now()
        const scored = []
        for (const doc of index.docs) {
            let score = 0
            for (const token of tokens) {
                const tf = doc.tf.get(token)
                if (!tf) continue
                const n = index.df.get(token) || 0
                const idf = Math.log(1 + (index.total - n + 0.5) / (n + 0.5))
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * doc.len / index.avgLen))
            }
            if (score <= 0) continue
            const ageDays = Math.max(0, now - doc.fact.at) / 86400_000
            const recency = 0.7 + 0.3 * Math.exp(-ageDays / 90)
            scored.push({ fact: doc.fact, score: score * (0.7 + 0.6 * doc.fact.importance) * recency })
        }
        return scored.sort((a, b2) => b2.score - a.score).slice(0, Math.max(1, Math.min(50, Number(limit) || 6)))
    }

    function recent(conversation, limit = 6) {
        const key = String(conversation ?? '')
        return load().facts
            .filter((fact) => visible(fact, key))
            .sort((a, b) => b.at - a.at)
            .slice(0, Math.max(1, Math.min(50, Number(limit) || 6)))
            .map((fact) => ({ fact, score: fact.importance }))
    }

    function stats() {
        const facts = load().facts
        return {
            facts: facts.length,
            active: facts.filter((fact) => fact.status === 'active').length,
            conversations: new Set(facts.map((fact) => fact.conversation)).size,
        }
    }

    return { file, add, search, recent, stats }
}
