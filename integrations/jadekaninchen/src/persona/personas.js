// 人格卡：Markdown 文件（可带 --- 头），放在 $DSH_HOME/mondchat/personas/。
// 首次启动把插件自带的人格复制到数据目录，之后以数据目录为准。
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const PLUGIN_DIR = dirname(dirname(dirname(fileURLToPath(import.meta.url))))
const BUNDLED = join(PLUGIN_DIR, 'personas')
const FALLBACK = '你是 Jadekaninchen（玉兔），一个在 MondChat 里聊天的伙伴。说话简短自然，不要假装拥有没有的工具或权限。'

export const safePersonaId = (id) => String(id ?? '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 40)

export function parsePersona(id, raw) {
    let text = String(raw ?? '').replace(/^﻿/, '')
    const meta = { id, name: id, tags: [] }
    const header = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/)
    if (header) {
        for (const line of header[1].split(/\r?\n/)) {
            const match = line.match(/^(\w+):\s*(.*)$/)
            if (!match) continue
            if (match[1] === 'name') meta.name = match[2].trim() || id
            if (match[1] === 'tags') {
                meta.tags = match[2].replace(/^\[|\]$/g, '').split(/[,，]/).map((tag) => tag.trim()).filter(Boolean)
            }
        }
        text = text.slice(header[0].length)
    }
    return { ...meta, body: text.trim() }
}

export function createPersonaStore({ home }) {
    const dir = join(home, 'personas')
    mkdirSync(dir, { recursive: true })

    function seed() {
        try {
            for (const name of readdirSync(BUNDLED)) {
                if (name.endsWith('.md') && !existsSync(join(dir, name))) {
                    copyFileSync(join(BUNDLED, name), join(dir, name))
                }
            }
        } catch {
            // 自带人格目录不在也不影响用户自己放的人格。
        }
    }

    function list() {
        seed()
        const out = []
        for (const name of readdirSync(dir)) {
            if (!name.endsWith('.md')) continue
            const id = safePersonaId(name.slice(0, -3))
            if (!id) continue
            try {
                const persona = parsePersona(id, readFileSync(join(dir, name), 'utf8'))
                out.push({ id, name: persona.name, tags: persona.tags, chars: persona.body.length })
            } catch {
                // 坏文件跳过，不影响其他人格。
            }
        }
        return out.sort((a, b) => a.name.localeCompare(b.name))
    }

    function read(id) {
        seed()
        const safe = safePersonaId(id)
        if (!safe) return null
        const file = join(dir, `${safe}.md`)
        if (!existsSync(file)) return null
        try {
            const raw = readFileSync(file, 'utf8')
            return { ...parsePersona(safe, raw), raw }
        } catch {
            return null
        }
    }

    /** 当前人格正文；找不到就退回列表第一个，再不行用兜底。 */
    function text(id) {
        const persona = read(id) || list().map((item) => read(item.id)).find(Boolean)
        return persona?.body || FALLBACK
    }

    return { dir, list, read, text, seed }
}
