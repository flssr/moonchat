// MondChat 插件的设置页：设置 → 插件 → MondChat。
// 只读快照：桥连没连上、有哪些会话、各自还积压多少。数据来自宿主的 /api/mondchat/status。
window.__ModuleLoader__.load({
  id: 'dsh-onebot',
  factory(require) {
    const React = require('react')
    const h = React.createElement
    const NS = 'dsh-onebot'
    const API = '/api/mondchat/status'

    const DICTS = {
      en: {
        tab: 'MondChat',
        bridge: 'Bridge',
        connected: 'Connected',
        disconnected: 'Disconnected',
        url: 'Address',
        groups: 'Groups',
        on: 'On',
        off: 'Off',
        workspace: 'Working folder',
        model: 'Model',
        modelDefault: 'DSH default',
        proactive: 'Proactive topic',
        proactiveValue: 'After {idle} quiet minutes, at most {max} per hour',
        quiet: 'Quiet hours',
        conversations: 'Connected conversations',
        empty: 'No MondChat message has arrived yet.',
        unread: '{count} pending',
        dropped: '({count} dropped while backed up)',
        live: 'Session live',
        cold: 'Session not live',
        lastActivity: 'Last message',
        loadFailed: 'Could not read status: {message}',
      },
      zh: {
        tab: 'MondChat',
        bridge: '桥',
        connected: '已连接',
        disconnected: '未连接',
        url: '地址',
        groups: '群聊',
        on: '开',
        off: '关',
        workspace: '工作目录',
        model: '模型',
        modelDefault: '跟随 DSH 默认',
        proactive: '主动话题',
        proactiveValue: '安静 {idle} 分钟后可起话头，每小时最多 {max} 次',
        quiet: '安静时段',
        conversations: '已接入的会话',
        empty: '还没有 MondChat 消息进来。',
        unread: '{count} 条待处理',
        dropped: '（{count} 条因积压被丢弃）',
        live: '会话在线',
        cold: '会话未在线',
        lastActivity: '最近消息',
        loadFailed: '读取状态失败：{message}',
      },
    }

    const S = {
      wrap: { padding: '20px 24px', display: 'grid', gap: 18, color: 'var(--dsw-alias-label-primary)', fontSize: 13 },
      card: {
        border: '1px solid var(--dsw-alias-border-l1)',
        borderRadius: 10,
        background: 'var(--dsw-alias-bg-layer-1)',
        padding: '14px 16px',
        display: 'grid',
        gap: 10,
      },
      head: { display: 'flex', alignItems: 'center', gap: 8, fontWeight: 600 },
      row: { display: 'flex', gap: 12, alignItems: 'baseline', minHeight: 20 },
      label: { color: 'var(--dsw-alias-label-secondary)', minWidth: 104 },
      value: { color: 'var(--dsw-alias-label-primary)' },
      mono: { fontFamily: 'ui-monospace, SFMono-Regular, Consolas, monospace', fontSize: 12, color: 'var(--dsw-alias-label-secondary)' },
      caption: { color: 'var(--dsw-alias-label-tertiary)', fontSize: 12 },
      dot: (ok) => ({
        width: 8,
        height: 8,
        borderRadius: 4,
        background: ok ? 'var(--dsw-alias-state-success-primary)' : 'var(--dsw-alias-state-idle-primary)',
      }),
      badge: {
        background: 'var(--dsw-alias-bg-layer-2)',
        borderRadius: 999,
        padding: '1px 8px',
        fontSize: 12,
        color: 'var(--dsw-alias-label-secondary)',
      },
      list: { display: 'grid', gap: 8 },
      item: {
        display: 'flex',
        gap: 10,
        alignItems: 'center',
        padding: '10px 12px',
        borderRadius: 8,
        border: '1px solid var(--dsw-alias-border-l1)',
        background: 'var(--dsw-alias-bg-base)',
      },
      itemTitle: { flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
      error: { color: 'var(--dsw-alias-state-error-primary)' },
    }

    const fill = (text, values) => String(text).replace(/\{(\w+)\}/g, (_, key) => (values[key] ?? ''))

    function field(t, label, value, style) {
      return h('div', { style: S.row },
        h('div', { style: S.label }, label),
        h('div', { style: style ?? S.value }, value))
    }

    function when(ts) {
      if (!ts) return '—'
      const date = new Date(ts)
      return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString()
    }

    function Page(props) {
      const t = props && props.t ? props.t : (key) => key
      const [data, setData] = React.useState(null)
      const [error, setError] = React.useState('')

      React.useEffect(() => {
        let alive = true
        async function load() {
          try {
            const response = await fetch(API, { cache: 'no-store' })
            if (!response.ok) throw new Error('HTTP ' + response.status)
            const next = await response.json()
            if (!alive) return
            setData(next)
            setError('')
          } catch (failure) {
            if (alive) setError(String((failure && failure.message) || failure))
          }
        }
        load()
        const timer = setInterval(load, 5000)
        return () => {
          alive = false
          clearInterval(timer)
        }
      }, [])

      if (!data) {
        return h('div', { style: S.wrap }, h('div', { style: error ? S.error : S.caption },
          error ? fill(t('loadFailed'), { message: error }) : '…'))
      }

      const bridge = data.bridge || {}
      const config = data.config || {}
      const proactive = config.proactive || {}
      const conversations = Array.isArray(data.conversations) ? data.conversations : []

      const bridgeCard = h('div', { style: S.card },
        h('div', { style: S.head }, h('span', { style: S.dot(bridge.connected) }), t('bridge')),
        field(t, t('url'), bridge.url || '—', S.mono),
        h('div', { style: S.row },
          h('div', { style: S.label }, bridge.connected ? t('connected') : t('disconnected')),
          h('div', { style: S.value }, bridge.connected ? t('connected') : t('disconnected'))))

      const configCard = h('div', { style: S.card },
        field(t, t('groups'), config.groups ? t('on') : t('off')),
        field(t, t('proactive'), fill(t('proactiveValue'), { idle: proactive.idleMinutes, max: proactive.maxPerHour })),
        field(t, t('quiet'), proactive.quietHours || '—', S.mono),
        field(t, t('model'), config.model && config.model.model ? `${config.model.provider || ''} / ${config.model.model}` : t('modelDefault'), S.mono),
        field(t, t('workspace'), config.workspace || '—', S.mono))

      const items = conversations.length === 0
        ? [h('div', { style: S.caption }, t('empty'))]
        : conversations.map((item) => h('div', { key: item.conversation, style: S.item },
          h('div', { style: S.itemTitle }, item.title || item.conversation),
          h('span', { style: S.badge }, item.live ? t('live') : t('cold')),
          item.unread > 0 ? h('span', { style: S.badge }, fill(t('unread'), { count: item.unread })) : null,
          item.dropped > 0 ? h('span', { style: S.badge }, fill(t('dropped'), { count: item.dropped })) : null,
          h('span', { style: S.caption }, `${t('lastActivity')} ${when(item.lastActivity)}`)))

      return h('div', { style: S.wrap },
        bridgeCard,
        configCard,
        h('div', { style: S.card },
          h('div', { style: S.head }, t('conversations')),
          h('div', { style: S.list }, items)))
    }

    return {
      inject: ['slots', 'locale'],
      apply(ctx) {
        ctx.effect(() => ctx.locale.register(NS, 'en', DICTS.en), 'dsh-onebot: en dictionary')
        ctx.effect(() => ctx.locale.register(NS, 'zh', DICTS.zh), 'dsh-onebot: zh dictionary')
        const t = ctx.locale.bind(NS)
        ctx.slots.inject('settings.plugins.tab', () => ctx.slots.register({
          name: 'settings.plugins.tab',
          id: 'mondchat-onebot',
          order: 40,
          label: () => t('tab'),
          locale: NS,
          inject: () => ({ t }),
        }, Page))
      },
    }
  },
})
