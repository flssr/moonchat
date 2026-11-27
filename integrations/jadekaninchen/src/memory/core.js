// 长期记忆入口：优先 SQLite + FTS5；运行时不支持 node:sqlite 时回退 JSON。
// 向量检索不在这里，目前主检索始终是 BM25。
import {
    conflicting,
    createJsonCoreStore,
    normalizeFact,
    similarity,
    tokenize,
} from './core-json.js'
import { createSqliteCoreStore } from './core-sqlite.js'

export { conflicting, normalizeFact, similarity, tokenize }

export function createCoreStore({ file, legacyFile = '' } = {}) {
    if (!file) throw new Error('长期记忆文件路径不能为空')
    if (String(file).endsWith('.json')) return createJsonCoreStore({ file })
    try {
        return createSqliteCoreStore({ file, legacyFile })
    } catch {
        // node:sqlite 不可用或 FTS5 建表失败：退回 JSON，至少不丢记忆能力。
        return createJsonCoreStore({ file: legacyFile || `${file}.json` })
    }
}
