// 人格卡：Markdown 文件（可带 --- 头），放在 $DSH_HOME/mondchat/personas/。
// 首次启动把插件自带的人格复制到数据目录，之后以数据目录为准。
import {
    copyFileSync,
    existsSync,
    mkdirSync,
    readdirSync,
    readFileSync,
    unlinkSync,
    writeFileSync,
} from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const PLUGIN_DIR = dirname(dirname(dirname(fileURLToPath(import.meta.url))))
const BUNDLED = join(PLUGIN_DIR, 'personas')
const FALLBACK = '你是 Jadekaninchen（玉兔），一个在 MondChat 里聊天的伙伴。说话简短自然，不要假装拥有没有的工具或权限。'

export const PERSONA_TEMPLATE = `---
name: 新人格
description: 一句话介绍这个人格
tags: [标签1, 标签2]
---

## 身份
你是谁、在什么场景里聊天。

## 说话方式
句子长短、语气、常用词、要不要用 Markdown、要不要用表情。

## 性格与偏好
在意什么、不喜欢什么、遇到不同意见怎么处理。

## 边界
不能做什么、不能假装拥有什么、隐私和群聊里的规矩。
`

const LIMITS = { name: 40, description: 120, tag: 20, tags: 8, body: 20_000 }
const oneLine = (value, max) => String(value ?? '').replace(/[\r\n]+/g, ' ').trim().slice(0, max)

export const safePersonaId = (id) => String(id ?? '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 40)

export function parsePersona(id, raw) {
    let text = String(raw ?? '').replace(/^﻿/, '')
    const meta = { id, name: id, description: '', tags: [] }
    const header = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/)
    if (header) {
        for (const line of header[1].split(/\r?\n/)) {
            const match = line.match(/^(\w+):\s*(.*)$/)
            if (!match) continue
            if (match[1] === 'name') meta.name = match[2].trim() || id
            if (match[1] === 'description') meta.description = match[2].trim()
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
        const marker = join(dir, '.seeded')
        if (existsSync(marker)) return
        try {
            for (const name of readdirSync(BUNDLED)) {
                if (name.endsWith('.md') && !existsSync(join(dir, name))) {
                    copyFileSync(join(BUNDLED, name), join(dir, name))
                }
            }
        } catch {
            // 自带人格目录不在也不影响用户自己放的人格。
        }
        try {
            writeFileSync(marker, '1')
        } catch {
            // 写不了标记就下次再试。
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
                out.push({
                    id,
                    name: persona.name,
                    description: persona.description,
                    tags: persona.tags,
                    chars: persona.body.length,
                })
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

    function save({ id, name, description = '', tags = [], body = '' }) {
        seed()
        const safe = safePersonaId(id)
        if (!safe) throw new Error('人格 id 只能用英文字母、数字、- 和 _')
        const cleanName = oneLine(name, LIMITS.name)
        if (!cleanName) throw new Error('人格名称不能为空')
        const cleanBody = String(body ?? '').trim()
        if (!cleanBody) throw new Error('人格正文不能为空')
        if (cleanBody.length > LIMITS.body) throw new Error(`人格正文不能超过 ${LIMITS.body} 字`)
        const cleanTags = (Array.isArray(tags) ? tags : String(tags ?? '').split(/[,，]/))
            .map((tag) => oneLine(tag, LIMITS.tag).replace(/[,[\]]/g, ''))
            .filter(Boolean)
            .slice(0, LIMITS.tags)
        const head = [
            '---',
            `name: ${cleanName}`,
            `description: ${oneLine(description, LIMITS.description)}`,
            `tags: [${cleanTags.join(', ')}]`,
            '---',
            '',
            cleanBody,
            '',
        ].join('\n')
        writeFileSync(join(dir, `${safe}.md`), head, 'utf8')
        return read(safe)
    }

    function remove(id) {
        const safe = safePersonaId(id)
        if (!safe) return false
        const file = join(dir, `${safe}.md`)
        if (!existsSync(file)) return false
        unlinkSync(file)
        return true
    }

    return { dir, list, read, text, seed, save, remove, template: PERSONA_TEMPLATE }
}
