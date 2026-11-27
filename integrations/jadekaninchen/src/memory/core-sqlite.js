// SQLite 后端：结构化事实 + FTS5 BM25。没有 sqlite-vec，不做向量检索。
// 只在 node:sqlite 可用时使用；不可用由 core.js 回退到 JSON。
import { existsSync, mkdirSync, readFileSync, renameSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname } from 'node:path'

import { conflicting, normalizeFact, similarity, tokenize } from './core-json.js'

const require = createRequire(import.meta.url)
let DatabaseSync = null
try {
    ({ DatabaseSync } = require('node:sqlite'))
} catch {
    // Node 没有 node:sqlite：wrapper 会走 JSON。
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS facts (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,
    search_text TEXT NOT NULL,
    conversation TEXT NOT NULL,
    subject TEXT NOT NULL DEFAULT '',
    subject_name TEXT NOT NULL DEFAULT '',
    at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    importance REAL NOT NULL DEFAULT 0.5,
    source TEXT NOT NULL DEFAULT 'extract',
    status TEXT NOT NULL DEFAULT 'active',
    valid_until INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS facts_conversation ON facts(conversation, status, at);
CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(search_text, content='facts', content_rowid='rowid');
CREATE TRIGGER IF NOT EXISTS facts_ai AFTER INSERT ON facts BEGIN
    INSERT INTO facts_fts(rowid, search_text) VALUES (new.rowid, new.search_text);
END;
CREATE TRIGGER IF NOT EXISTS facts_ad AFTER DELETE ON facts BEGIN
    INSERT INTO facts_fts(facts_fts, rowid, search_text) VALUES ('delete', old.rowid, old.search_text);
END;
CREATE TRIGGER IF NOT EXISTS facts_au AFTER UPDATE ON facts BEGIN
    INSERT INTO facts_fts(facts_fts, rowid, search_text) VALUES ('delete', old.rowid, old.search_text);
    INSERT INTO facts_fts(rowid, search_text) VALUES (new.rowid, new.search_text);
END;
PRAGMA user_version = 1;
`

const searchText = (fact) => tokenize(`${fact.text} ${fact.subjectName}`).join(' ')

function rowToFact(row) {
    return {
        rowid: Number(row.rowid) || 0,
        id: row.id,
        text: row.text,
        conversation: row.conversation,
        subject: row.subject,
        subjectName: row.subject_name,
        at: Number(row.at),
        createdAt: Number(row.created_at),
        updatedAt: Number(row.updated_at),
        importance: Number(row.importance),
        source: row.source,
        status: row.status,
        validUntil: Number(row.valid_until) || 0,
    }
}

function ftsQuery(tokens) {
    return tokens.map((token) => `"${String(token).replace(/"/g, '""')}"`).join(' OR ')
}

export function createSqliteCoreStore({ file, legacyFile = '' }) {
    if (!DatabaseSync) throw new Error('当前运行时没有 node:sqlite')
    if (!file) throw new Error('长期记忆数据库路径不能为空')
    mkdirSync(dirname(file), { recursive: true })
    const db = new DatabaseSync(file)
    db.exec('PRAGMA busy_timeout = 2000; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;')
    db.exec(SCHEMA)

    const insert = db.prepare(`
        INSERT INTO facts (id, text, search_text, conversation, subject, subject_name, at,
            created_at, updated_at, importance, source, status, valid_until)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    const findActive = db.prepare(`
        SELECT rowid, * FROM facts WHERE conversation = ? AND subject = ? AND status = 'active'`)
    const update = db.prepare(`
        UPDATE facts SET text = ?, search_text = ?, importance = ?, at = ?, updated_at = ?, source = ?
        WHERE rowid = ?`)
    const stale = db.prepare("UPDATE facts SET status = 'stale', valid_until = ?, updated_at = ? WHERE rowid = ?")
    const recentRows = db.prepare(`
        SELECT rowid, * FROM facts WHERE conversation = ? AND status = 'active' ORDER BY at DESC LIMIT ?`)
    const countAll = db.prepare('SELECT count(*) AS count FROM facts')
    const countActive = db.prepare("SELECT count(*) AS count FROM facts WHERE status = 'active'")
    const countConversations = db.prepare('SELECT count(DISTINCT conversation) AS count FROM facts')
    const ownRows = db.prepare('SELECT rowid, status, importance, at FROM facts WHERE conversation = ?')
    const removeRow = db.prepare('DELETE FROM facts WHERE rowid = ?')

    function insertFact(entry) {
        insert.run(
            entry.id,
            entry.text,
            searchText(entry),
            entry.conversation,
            entry.subject,
            entry.subjectName,
            entry.at,
            entry.createdAt,
            entry.updatedAt,
            entry.importance,
            entry.source,
            entry.status,
            entry.validUntil,
        )
        return entry
    }

    /** 旧版本把事实存在 memory-core.json：第一次打开空库时导进来，成功后改名留档。 */
    function migrateLegacy() {
        if (!legacyFile || !existsSync(legacyFile) || countAll.get().count > 0) return
        let parsed
        try {
            parsed = JSON.parse(readFileSync(legacyFile, 'utf8'))
        } catch {
            return
        }
        const facts = Array.isArray(parsed?.facts) ? parsed.facts.map(normalizeFact).filter(Boolean) : []
        if (facts.length === 0) return
        db.exec('BEGIN IMMEDIATE')
        try {
            for (const fact of facts) insertFact(fact)
            db.exec('COMMIT')
            renameSync(legacyFile, `${legacyFile}.migrated`)
        } catch (error) {
            db.exec('ROLLBACK')
            throw error
        }
    }

    migrateLegacy()

    function add(fact) {
        const entry = normalizeFact({ ...fact, id: fact?.id || undefined })
        if (!entry) return null
        const candidates = findActive.all(entry.conversation, entry.subject).map(rowToFact)
        const old = candidates.find((item) => similarity(item.text, entry.text) >= 0.6)
        if (old && !conflicting(old.text, entry.text)) {
            const text = entry.text.length > old.text.length ? entry.text : old.text
            update.run(text, searchText({ ...old, text }), Math.max(old.importance, entry.importance),
                Math.max(old.at, entry.at), Date.now(), entry.source, old.rowid)
            return { ...old, text }
        }
        if (old) stale.run(entry.at, Date.now(), old.rowid)
        insertFact(entry)

        const own = ownRows.all(entry.conversation)
        if (own.length > 300) {
            const drop = own
                .sort((a, b) => Number(b.status === 'stale') - Number(a.status === 'stale')
                    || Number(a.importance) - Number(b.importance)
                    || Number(a.at) - Number(b.at))
                .slice(0, own.length - 300)
            for (const row of drop) removeRow.run(row.rowid)
        }
        return entry
    }

    function search(query, { conversation, limit = 6 } = {}) {
        const key = String(conversation ?? '')
        const tokens = [...new Set(tokenize(query))]
        if (tokens.length === 0) return recent(key, limit)
        let rows
        try {
            rows = db.prepare(`
                SELECT f.*, bm25(facts_fts) AS rank
                FROM facts_fts JOIN facts f ON f.rowid = facts_fts.rowid
                WHERE facts_fts MATCH ? AND f.conversation = ? AND f.status = 'active'
                ORDER BY rank LIMIT 50`).all(ftsQuery(tokens), key)
        } catch {
            return []
        }
        const now = Date.now()
        return rows
            .map((row) => {
                const fact = rowToFact(row)
                const ageDays = Math.max(0, now - fact.at) / 86400_000
                const recency = 0.7 + 0.3 * Math.exp(-ageDays / 90)
                return { fact, score: -Number(row.rank) * (0.7 + 0.6 * fact.importance) * recency }
            })
            .sort((a, b) => b.score - a.score)
            .slice(0, Math.max(1, Math.min(50, Number(limit) || 6)))
    }

    function recent(conversation, limit = 6) {
        return recentRows.all(String(conversation ?? ''), Math.max(1, Math.min(50, Number(limit) || 6)))
            .map((row) => ({ fact: rowToFact(row), score: Number(row.importance) }))
    }

    function stats() {
        return {
            facts: Number(countAll.get().count),
            active: Number(countActive.get().count),
            conversations: Number(countConversations.get().count),
        }
    }

    return { file, add, search, recent, stats, close: () => db.close() }
}
