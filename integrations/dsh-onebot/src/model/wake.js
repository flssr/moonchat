// 唤醒原因：决定用哪套提示词模板。
export const INBOUND = 'inbound'
export const PROACTIVE = 'proactive'
export const MANUAL = 'manual'

export const inboundReason = (pending) => ({ kind: INBOUND, pending: Math.max(1, Number(pending) || 1) })
export const proactiveReason = (idleMinutes) => ({ kind: PROACTIVE, idleMinutes: Math.max(1, Number(idleMinutes) || 1) })
export const manualReason = () => ({ kind: MANUAL })

export const isProactive = (reason) => reason?.kind === PROACTIVE
