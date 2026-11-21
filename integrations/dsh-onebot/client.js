// MondChat 插件的侧栏面板：和「便签」「自动化任务」并排，点图标在主栏打开。
// 只读快照：桥连没连上、有哪些会话、各自还积压多少。数据来自宿主的 /api/mondchat/status。
window.__ModuleLoader__.load({
  id: 'dsh-onebot',
  factory(require) {
    const React = require('react')
    const h = React.createElement
    const NS = 'dsh-onebot'
    const API = '/api/mondchat/status'
    const PANEL_ID = 'mondchat'

    const DICTS = {
      en: {
        panel: 'MondChat',
        title: 'MondChat',
        subtitle: 'Direct chats and groups bridged into DSH sessions.',
        bridge: 'Bridge',
        connected: 'Connected',
        disconnected: 'Disconnected',
        url: 'Address',
        process: 'Process / link',
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
        empty: 'No MondChat message has arrived yet. Send one to the bot account to start.',
        unread: '{count} pending',
        dropped: '({count} dropped while backed up)',
        live: 'Session live',
        cold: 'Session not live',
        lastActivity: 'Last message',
        error: 'Error',
        loadFailed: 'Could not read status: {message}',
      },
      zh: {
        panel: 'MondChat',
        title: 'MondChat',
        subtitle: '把 MondChat 的私聊和群接进 DSH 会话。',
        bridge: '桥',
        connected: '已连接',
        disconnected: '未连接',
        url: '地址',
        process: '进程 / 连接',
        error: '错误',
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
        empty: '还没有 MondChat 消息进来。给 bot 账号发一条私聊就会出现在这里。',
        unread: '{count} 条待处理',
        dropped: '（{count} 条因积压被丢弃）',
        live: '会话在线',
        cold: '会话未在线',
        lastActivity: '最近消息',
        loadFailed: '读取状态失败：{message}',
      },
    }

    const S = {
      page: {
        height: '100%',
        overflowY: 'auto',
        padding: '28px 32px 40px',
        display: 'grid',
        gap: 16,
        alignContent: 'start',
        color: 'var(--dsw-alias-label-primary)',
        fontSize: 13,
      },
      titleRow: { display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' },
      title: { fontSize: 18, fontWeight: 600 },
      subtitle: { color: 'var(--dsw-alias-label-tertiary)', fontSize: 12 },
      card: {
        border: '1px solid var(--dsw-alias-border-l1)',
        borderRadius: 10,
        background: 'var(--dsw-alias-bg-layer-1)',
        padding: '14px 16px',
        display: 'grid',
        gap: 10,
        maxWidth: 760,
      },
      head: { display: 'flex', alignItems: 'center', gap: 8, fontWeight: 600 },
      row: { display: 'flex', gap: 12, alignItems: 'baseline', minHeight: 20 },
      label: { color: 'var(--dsw-alias-label-secondary)', minWidth: 104 },
      mono: {
        fontFamily: 'ui-monospace, SFMono-Regular, Consolas, monospace',
        fontSize: 12,
        color: 'var(--dsw-alias-label-secondary)',
      },
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
        whiteSpace: 'nowrap',
      },
      list: { display: 'grid', gap: 8, maxWidth: 760 },
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

    // 这些插槽只声明了 id/order/label（main 只有 key）；翻译走模块内绑定，
    // bind() 每次读当前语言，所以切语言不用重新注册。
    let boundT = (key) => key

    function field(t, label, value, style) {
      return h('div', { style: S.row },
        h('div', { style: S.label }, label),
        h('div', { style: style ?? { color: 'var(--dsw-alias-label-primary)' } }, value))
    }

    function when(ts) {
      if (!ts) return '—'
      const date = new Date(ts)
      return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString()
    }

    function Icon(props) {
      const size = (props && props.size) || 18
      return h('svg', {
        width: size,
        height: size,
        viewBox: '0 0 24 24',
        fill: 'none',
        'aria-hidden': true,
        style: { display: 'block' },
      },
      h('rect', { x: 2.5, y: 4.5, width: 19, height: 13, rx: 3.5, stroke: 'currentColor', strokeWidth: 1.6 }),
      h('path', { d: 'M7 20.2l3.4-2.7', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round' }),
      h('circle', { cx: 8.2, cy: 11, r: 1.35, fill: 'currentColor' }),
      h('circle', { cx: 12, cy: 11, r: 1.35, fill: 'currentColor' }),
      h('circle', { cx: 15.8, cy: 11, r: 1.35, fill: 'currentColor' }))
    }

    function PanelPage() {
      const t = boundT
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

      const header = h('div', { style: { display: 'grid', gap: 4 } },
        h('div', { style: S.titleRow }, h('div', { style: S.title }, t('title'))),
        h('div', { style: S.subtitle }, t('subtitle')))

      if (!data) {
        return h('div', { style: S.page }, header,
          h('div', { style: error ? S.error : S.caption },
            error ? fill(t('loadFailed'), { message: error }) : '…'))
      }

      const bridge = data.bridge || {}
      const config = data.config || {}
      const proactive = config.proactive || {}
      const conversations = Array.isArray(data.conversations) ? data.conversations : []
      const connected = bridge.connection === 'connected'

      const bridgeCard = h('div', { style: S.card },
        h('div', { style: S.head }, h('span', { style: S.dot(connected) }), t('bridge'),
          h('span', { style: S.badge }, connected ? t('connected') : t('disconnected'))),
        field(t, t('url'), bridge.url || '—', S.mono),
        field(t, t('process'), `${bridge.process || '—'} / ${bridge.connection || '—'}`, S.mono),
        bridge.lastError ? field(t, t('error'), bridge.lastError, S.error) : null)

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

      return h('div', { style: S.page },
        header,
        bridgeCard,
        configCard,
        h('div', { style: { display: 'grid', gap: 10 } },
          h('div', { style: S.head }, t('conversations')),
          h('div', { style: S.list }, items)))
    }

    return {
      inject: ['slots', 'locale'],
      apply(ctx) {
        ctx.effect(() => ctx.locale.register(NS, 'en', DICTS.en), 'dsh-onebot: en dictionary')
        ctx.effect(() => ctx.locale.register(NS, 'zh', DICTS.zh), 'dsh-onebot: zh dictionary')
        const t = ctx.locale.bind(NS)
        boundT = t

        // 侧栏图标：id 就是主栏要打开的 key，和便签、自动化任务同一排。
        ctx.slots.inject('sidebar.panellist', () => ctx.slots.register({
          name: 'sidebar.panellist',
          id: PANEL_ID,
          order: 5,
          label: () => t('panel'),
          locale: NS,
        }, Icon))

        // 主栏页面：点图标切过来，和便签页同一形态。
        ctx.slots.inject('main', () => ctx.slots.register({
          name: 'main',
          key: PANEL_ID,
          locale: NS,
        }, PanelPage))
      },
    }
  },
})
