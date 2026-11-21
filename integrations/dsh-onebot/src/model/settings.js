// 设置实体：全局的一份，叠上每个会话的覆盖。纯函数，不碰宿主也不读环境。

export const LANGUAGES = ['zh', 'en']

export const DEFAULTS = {
    /** 空字符串 = 跟随宿主时区。 */
    timezone: '',
    /** 回复语言，写进提示词的 <language>。 */
    language: 'zh',
    groups: true,
    model: null,
    workspace: '',
    proactive: {
        enabled: true,
        idleMinutes: 60,
        maxPerHour: 2,
        quietHours: '23:00-08:00',
    },
    /** conversation key → 覆盖项；缺省字段继承全局。 */
    conversations: {},
}

const positive = (value, fallback) => {
    const number = Number(value)
    return Number.isFinite(number) && number > 0 ? number : fallback
}

const text = (value, fallback) => (typeof value === 'string' && value.trim() ? value.trim() : fallback)

/** 插件 config → 全局设置。认不出的值一律退回默认，不让坏配置把插件带偏。 */
export function normalizeGlobal(config = {}) {
    const proactive = config.proactive ?? {}
    return {
        timezone: text(config.timezone, DEFAULTS.timezone),
        language: LANGUAGES.includes(config.language) ? config.language : DEFAULTS.language,
        groups: config.groups !== false,
        model: config.model?.provider && config.model?.model
            ? { provider: String(config.model.provider), model: String(config.model.model) }
            : null,
        workspace: text(config.workspace, DEFAULTS.workspace),
        proactive: {
            enabled: proactive.enabled !== false,
            idleMinutes: positive(proactive.idleMinutes, DEFAULTS.proactive.idleMinutes),
            maxPerHour: positive(proactive.maxPerHour, DEFAULTS.proactive.maxPerHour),
            quietHours: typeof proactive.quietHours === 'string' ? proactive.quietHours : DEFAULTS.proactive.quietHours,
        },
        conversations: config.conversations && typeof config.conversations === 'object' ? config.conversations : {},
    }
}

/** 某个会话最终生效的闸门：会话覆盖优先，缺的继承全局。 */
export function settingsFor(settings, conversation) {
    const override = settings.conversations?.[conversation] ?? {}
    return {
        enabled: override.enabled ?? settings.proactive.enabled,
        idleMinutes: positive(override.idleMinutes, settings.proactive.idleMinutes),
        maxPerHour: positive(override.maxPerHour, settings.proactive.maxPerHour),
        quietHours: typeof override.quietHours === 'string' ? override.quietHours : settings.proactive.quietHours,
    }
}

/** 时区没配就按宿主本地；配错了也退回本地，不让 Intl 抛。 */
export function zoneOf(settings) {
    return settings.timezone || undefined
}

const MINUTES = /^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$/

/** '23:00-08:00' 这种跨零点区间；时区按设置走。 */
export function inQuietHours(now, range, timeZone) {
    const match = MINUTES.exec(String(range ?? ''))
    if (!match) return false
    const minutes = minutesOfDay(now, timeZone)
    const start = Number(match[1]) * 60 + Number(match[2])
    const end = Number(match[3]) * 60 + Number(match[4])
    return start <= end ? minutes >= start && minutes < end : minutes >= start || minutes < end
}

function minutesOfDay(now, timeZone) {
    const date = now instanceof Date ? now : new Date(now)
    if (!timeZone) return date.getHours() * 60 + date.getMinutes()
    try {
        const parts = new Intl.DateTimeFormat('en-GB', {
            timeZone,
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
        }).formatToParts(date)
        const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? 0)
        const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? 0)
        return hour * 60 + minute
    } catch {
        return date.getHours() * 60 + date.getMinutes()
    }
}

/** 提示词里 <time> 用的本地时间：2026-11-22T00:17:05+08:00。 */
export function isoInZone(now, timeZone) {
    const date = now instanceof Date ? now : new Date(now)
    const zone = timeZone || undefined
    try {
        const stamp = new Intl.DateTimeFormat('sv-SE', {
            timeZone: zone,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false,
        }).format(date).replace(' ', 'T')
        const offset = new Intl.DateTimeFormat('en-US', {
            timeZone: zone,
            timeZoneName: 'longOffset',
        }).formatToParts(date).find((part) => part.type === 'timeZoneName')?.value ?? 'GMT'
        const suffix = offset === 'GMT' ? '+00:00' : offset.replace('GMT', '')
        return `${stamp}${suffix}`
    } catch {
        return date.toISOString()
    }
}
