// Jadekaninchen 的侧栏面板：和「便签」「自动化任务」并排，点图标在主栏打开。
// 数据来自宿主的 /api/mondchat/* 路由；面板只做呈现与提交，判定在 service。
window.__ModuleLoader__.load({
  id: 'jadekaninchen',
  factory(require) {
    const React = require('react')
    const h = React.createElement
    const NS = 'jadekaninchen'
    const STATUS = '/api/mondchat/status'
    const BRIDGE = '/api/mondchat/bridge'
    const SETTINGS = '/api/mondchat/settings'
    const PERSONAS = '/api/mondchat/personas'
    const PANEL_ID = 'jadekaninchen'

    const DICTS = {
      en: {
        panel: 'Jadekaninchen',
        title: 'Jadekaninchen',
        subtitle: 'MondChat direct chats and groups bridged into DSH sessions.',
        bridge: 'Bridge',
        connected: 'Connected',
        disconnected: 'Disconnected',
        url: 'Address',
        process: 'Process / link',
        error: 'Error',
        start: 'Start bridge',
        stop: 'Stop bridge',
        restart: 'Restart',
        busy: 'Working…',
        managed: 'The bridge runs as a child of DSH; stopping the plugin stops it too.',
        unmanaged: 'This host cannot start processes; run the bridge yourself.',
        external: 'A bridge is already answering on this port (started outside the plugin), so starting another is disabled.',
        settings: 'Settings',
        persona: 'Persona',
        personaHint: 'Markdown cards live in the plugin data folder under personas/.',
        personaEditor: 'Persona editor',
        personaId: 'ID',
        personaName: 'Name',
        personaDescription: 'Description',
        personaTags: 'Tags',
        personaBody: 'Body',
        personaNew: 'New',
        personaSave: 'Save persona',
        personaDelete: 'Delete',
        personaTemplate: 'Fill template',
        personaFormat: 'Format: name / description / tags in frontmatter, then body sections 身份 / 说话方式 / 性格与偏好 / 边界.',
        personaSaved: 'Persona saved.',
        personaDeleted: 'Persona deleted.',
        personaRequired: 'ID, name and body are required.',
        personaConfirmDelete: 'Delete this persona file?',
        timezone: 'Time zone',
        timezoneHint: 'IANA zone such as Asia/Shanghai; empty follows the host.',
        bridgeUrl: 'Bridge address',
        bridgeHint: 'A spawned bridge binds this address. Effective now:',
        language: 'Reply language',
        groups: 'Groups',
        save: 'Save',
        savedReload: 'Saved. The plugin reloads and the bridge reconnects once.',
        conversations: 'Connected conversations',
        empty: 'No MondChat message has arrived yet. Send one to the bot account to start.',
        unread: '{count} pending',
        dropped: '({count} dropped while backed up)',
        live: 'Session live',
        cold: 'Session not live',
        lastActivity: 'Last message',
        gate: 'Proactive',
        idle: 'Idle minutes',
        perHour: 'Max per hour',
        quiet: 'Quiet hours',
        reset: 'Reset to global',
        edit: 'Edit',
        close: 'Close',
        loadFailed: 'Could not read status: {message}',
        actionFailed: 'Action failed: {message}',
      },
      zh: {
        panel: 'Jadekaninchen',
        title: 'Jadekaninchen',
        subtitle: '把 MondChat 的私聊和群接进 DSH 会话。',
        bridge: '桥',
        connected: '已连接',
        disconnected: '未连接',
        url: '地址',
        process: '进程 / 连接',
        error: '错误',
        start: '启动桥',
        stop: '停止桥',
        restart: '重启',
        busy: '处理中…',
        managed: '桥由 DSH 作为子进程托管，插件卸载时会一起停掉。',
        unmanaged: '这个宿主不能启动进程，桥需要你自己跑。',
        external: '这个端口上已经有桥在应答（插件之外启动的），所以不再允许重复启动。',
        settings: '设置',
        persona: '人格',
        personaHint: '人格卡是 personas/ 下的 Markdown 文件，改完点保存。',
        personaEditor: '人格编辑器',
        personaId: 'ID',
        personaName: '名称',
        personaDescription: '简介',
        personaTags: '标签',
        personaBody: '正文',
        personaNew: '新建',
        personaSave: '保存人格',
        personaDelete: '删除',
        personaTemplate: '填入模板',
        personaFormat: '格式：frontmatter 写 name / description / tags，正文建议按 身份 / 说话方式 / 性格与偏好 / 边界 四段写。',
        personaSaved: '人格已保存。',
        personaDeleted: '人格已删除。',
        personaRequired: 'ID、名称和正文不能为空。',
        personaConfirmDelete: '确定删除这个人格文件？',
        timezone: '时区',
        timezoneHint: 'IANA 名称，如 Asia/Shanghai；留空跟随宿主。',
        bridgeUrl: '桥地址',
        bridgeHint: '托管的桥会绑到这个地址。当前生效：',
        language: '回复语言',
        groups: '群聊',
        save: '保存',
        savedReload: '已保存。插件会重装一次，桥跟着重连。',
        conversations: '已接入的会话',
        empty: '还没有 MondChat 消息进来。给 bot 账号发一条私聊就会出现在这里。',
        unread: '{count} 条待处理',
        dropped: '（{count} 条因积压被丢弃）',
        live: '会话在线',
        cold: '会话未在线',
        lastActivity: '最近消息',
        gate: '主动话题',
        idle: '安静分钟',
        perHour: '每小时上限',
        quiet: '免打扰时段',
        reset: '回到全局',
        edit: '编辑',
        close: '收起',
        loadFailed: '读取状态失败：{message}',
        actionFailed: '操作失败：{message}',
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
        maxWidth: 820,
      },
      head: { display: 'flex', alignItems: 'center', gap: 8, fontWeight: 600 },
      actions: { display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' },
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
      button: {
        border: '1px solid var(--dsw-alias-border-l1)',
        background: 'var(--dsw-alias-bg-layer-2)',
        color: 'var(--dsw-alias-label-primary)',
        borderRadius: 6,
        padding: '3px 10px',
        fontSize: 12,
        cursor: 'pointer',
      },
      input: {
        border: '1px solid var(--dsw-alias-border-l1)',
        background: 'var(--dsw-alias-bg-base)',
        color: 'var(--dsw-alias-label-primary)',
        borderRadius: 6,
        padding: '3px 8px',
        fontSize: 12,
        width: 140,
      },
      textarea: {
        border: '1px solid var(--dsw-alias-border-l1)',
        background: 'var(--dsw-alias-bg-base)',
        color: 'var(--dsw-alias-label-primary)',
        borderRadius: 6,
        padding: '8px 10px',
        fontSize: 12,
        width: '100%',
        minHeight: 240,
        resize: 'vertical',
        lineHeight: 1.6,
        fontFamily: 'ui-monospace, SFMono-Regular, Consolas, monospace',
      },
      list: { display: 'grid', gap: 8, maxWidth: 820 },
      item: {
        display: 'grid',
        gap: 8,
        padding: '10px 12px',
        borderRadius: 8,
        border: '1px solid var(--dsw-alias-border-l1)',
        background: 'var(--dsw-alias-bg-base)',
      },
      itemRow: { display: 'flex', gap: 10, alignItems: 'center' },
      itemTitle: { flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
      error: { color: 'var(--dsw-alias-state-error-primary)' },
      notice: { color: 'var(--dsw-alias-state-success-primary)', fontSize: 12 },
    }

    const fill = (text, values) => String(text).replace(/\{(\w+)\}/g, (_, key) => (values[key] ?? ''))
    const BODY_TEMPLATE = [
      '## 身份',
      '你是谁、在什么场景里聊天。',
      '',
      '## 说话方式',
      '句子长短、语气、常用词、要不要用 Markdown、要不要用表情。',
      '',
      '## 性格与偏好',
      '在意什么、不喜欢什么、遇到不同意见怎么处理。',
      '',
      '## 边界',
      '不能做什么、不能假装拥有什么、隐私和群聊里的规矩。',
    ].join('\n')

    // 这些插槽只声明了 id/order/key；翻译走模块内绑定。
    let boundT = (key) => key

    const field = (t, label, value, style) => h('div', { style: S.row },
      h('div', { style: S.label }, label),
      h('div', { style: style ?? { color: 'var(--dsw-alias-label-primary)' } }, value))

    const when = (ts) => {
      if (!ts) return '—'
      const date = new Date(ts)
      return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString()
    }

    async function post(path, body) {
      const response = await fetch(path, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || ('HTTP ' + response.status))
      return data
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
      const [busy, setBusy] = React.useState('')
      const [notice, setNotice] = React.useState('')
      const [draft, setDraft] = React.useState(null)
      const [editing, setEditing] = React.useState('')
      const [gateDraft, setGateDraft] = React.useState({})
      const [personaDraft, setPersonaDraft] = React.useState(null)
      const [personaBusy, setPersonaBusy] = React.useState('')
      const [personaNotice, setPersonaNotice] = React.useState('')
      const [personaError, setPersonaError] = React.useState('')
      const [personaCreating, setPersonaCreating] = React.useState(false)
      const loadedPersona = React.useRef('')

      React.useEffect(() => {
        let alive = true
        async function load() {
          try {
            const response = await fetch(STATUS, { cache: 'no-store' })
            if (!response.ok) throw new Error('HTTP ' + response.status)
            const next = await response.json()
            if (!alive) return
            setData(next)
            setError('')
            setDraft((current) => current ?? {
              bridge: next.bridge?.url ?? '',
              persona: next.config?.persona ?? 'jadekaninchen',
              timezone: next.config?.timezone ?? '',
              language: next.config?.language ?? 'zh',
              groups: next.config?.groups !== false,
            })
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

      React.useEffect(() => {
        const id = data?.config?.persona
        if (!id || loadedPersona.current === id) return undefined
        loadedPersona.current = id
        let alive = true
        post(PERSONAS, { action: 'read', id })
          .then((result) => {
            if (!alive) return
            setPersonaDraft({
              ...result.persona,
              tags: (result.persona.tags || []).join(', '),
            })
            setPersonaError('')
          })
          .catch((failure) => {
            if (alive) setPersonaError(String((failure && failure.message) || failure))
          })
        return () => { alive = false }
      }, [data?.config?.persona])

      const run = async (label, task) => {
        setBusy(label)
        setNotice('')
        setError('')
        try {
          const result = await task()
          setNotice(result?.reload ? t('savedReload') : '')
        } catch (failure) {
          setError(fill(t('actionFailed'), { message: String((failure && failure.message) || failure) }))
        } finally {
          setBusy('')
        }
      }

      const openPersona = async (id) => {
        if (!id) return
        setPersonaBusy('read')
        setPersonaError('')
        setPersonaNotice('')
        try {
          const result = await post(PERSONAS, { action: 'read', id })
          setPersonaDraft({ ...result.persona, tags: (result.persona.tags || []).join(', ') })
          setPersonaCreating(false)
        } catch (failure) {
          setPersonaError(String((failure && failure.message) || failure))
        } finally {
          setPersonaBusy('')
        }
      }

      const newPersona = () => {
        setPersonaCreating(true)
        setPersonaError('')
        setPersonaNotice('')
        setPersonaDraft({
          id: '',
          name: '',
          description: '',
          tags: '',
          body: BODY_TEMPLATE,
        })
      }

      const savePersona = async () => {
        if (!personaDraft) return
        const id = String(personaDraft.id || '').trim()
        const name = String(personaDraft.name || '').trim()
        const body = String(personaDraft.body || '').trim()
        if (!id || !name || !body) {
          setPersonaError(t('personaRequired'))
          return
        }
        setPersonaBusy('save')
        setPersonaError('')
        setPersonaNotice('')
        try {
          const result = await post(PERSONAS, {
            action: 'save',
            id,
            name,
            description: personaDraft.description || '',
            tags: personaDraft.tags || '',
            body,
          })
          setPersonaDraft({ ...result.persona, tags: (result.persona.tags || []).join(', ') })
          setPersonaCreating(false)
          loadedPersona.current = result.persona.id
          setData((current) => (current ? { ...current, personas: result.personas || current.personas } : current))
          setDraft((current) => (current ? { ...current, persona: result.persona.id } : current))
          setPersonaNotice(t('personaSaved'))
        } catch (failure) {
          setPersonaError(String((failure && failure.message) || failure))
        } finally {
          setPersonaBusy('')
        }
      }

      const deletePersona = async () => {
        if (!personaDraft?.id) return
        if (typeof window !== 'undefined' && !window.confirm(t('personaConfirmDelete'))) return
        setPersonaBusy('delete')
        setPersonaError('')
        setPersonaNotice('')
        try {
          const result = await post(PERSONAS, { action: 'delete', id: personaDraft.id })
          setData((current) => (current ? { ...current, personas: result.personas || current.personas } : current))
          setPersonaNotice(t('personaDeleted'))
          setPersonaDraft(null)
          loadedPersona.current = ''
          await openPersona(data?.config?.persona)
        } catch (failure) {
          setPersonaError(String((failure && failure.message) || failure))
        } finally {
          setPersonaBusy('')
        }
      }

      const header = h('div', { style: { display: 'grid', gap: 4 } },
        h('div', { style: S.titleRow }, h('div', { style: S.title }, t('title'))),
        h('div', { style: S.subtitle }, t('subtitle')))

      if (!data) {
        return h('div', { style: S.page }, header,
          h('div', { style: error ? S.error : S.caption },
            error ? fill(t('loadFailed'), { message: error }) : '…'))
      }

      const bridge = data.bridge || {}
      const controls = data.controls || {}
      const config = data.config || {}
      const conversations = Array.isArray(data.conversations) ? data.conversations : []
      const connected = bridge.connection === 'connected'
      const running = bridge.process === 'running'
      // 端口上已经有桥在应答（用户自己跑的）：别再起第二个，会撞端口。
      const external = connected && !controls.inProcess

      const bridgeButtons = h('div', { style: S.actions },
        h('button', {
          type: 'button',
          style: S.button,
          disabled: !controls.bridge || busy !== '' || running || external,
          onClick: () => run('start', () => post(BRIDGE, { action: 'start' })),
        }, busy === 'start' ? t('busy') : t('start')),
        h('button', {
          type: 'button',
          style: S.button,
          disabled: !controls.bridge || busy !== '' || !running,
          onClick: () => run('stop', () => post(BRIDGE, { action: 'stop' })),
        }, busy === 'stop' ? t('busy') : t('stop')),
        h('button', {
          type: 'button',
          style: S.button,
          disabled: !controls.bridge || busy !== '' || !controls.inProcess || !running,
          onClick: () => run('restart', () => post(BRIDGE, { action: 'restart' })),
        }, busy === 'restart' ? t('busy') : t('restart')))

      const bridgeCard = h('div', { style: S.card },
        h('div', { style: S.head }, h('span', { style: S.dot(connected) }), t('bridge'),
          h('span', { style: S.badge }, connected ? t('connected') : t('disconnected'))),
        field(t, t('url'), bridge.url || '—', S.mono),
        field(t, t('process'), `${bridge.process || '—'} / ${bridge.connection || '—'}`, S.mono),
        bridge.lastError ? field(t, t('error'), bridge.lastError, S.error) : null,
        bridgeButtons,
        h('div', { style: S.caption }, controls.bridge ? t('managed') : t('unmanaged')),
        external ? h('div', { style: S.caption }, t('external')) : null)

      const settingsCard = h('div', { style: S.card },
        h('div', { style: S.head }, t('settings')),
        h('div', { style: S.row }, h('div', { style: S.label }, t('bridgeUrl')),
          h('input', {
            style: { ...S.input, width: 220 },
            value: draft?.bridge ?? '',
            placeholder: 'ws://127.0.0.1:6700',
            onChange: (event) => setDraft({ ...draft, bridge: event.target.value }),
          })),
        h('div', { style: S.caption }, `${t('bridgeHint')} ${controls.host}:${controls.port}`),
        h('div', { style: S.row }, h('div', { style: S.label }, t('persona')),
          h('select', {
            style: S.input,
            value: draft?.persona ?? '',
            onChange: (event) => setDraft({ ...draft, persona: event.target.value }),
          },
          ...(Array.isArray(data.personas) && data.personas.length > 0
            ? data.personas.map((persona) => h('option', { key: persona.id, value: persona.id }, persona.name || persona.id))
            : [h('option', { key: 'current', value: draft?.persona ?? '' }, draft?.persona ?? '')]))),
        h('div', { style: S.caption }, t('personaHint')),
        h('div', { style: S.row }, h('div', { style: S.label }, t('timezone')),
          h('input', {
            style: S.input,
            value: draft?.timezone ?? '',
            placeholder: 'Asia/Shanghai',
            onChange: (event) => setDraft({ ...draft, timezone: event.target.value }),
          })),
        h('div', { style: S.caption }, t('timezoneHint')),
        h('div', { style: S.row }, h('div', { style: S.label }, t('language')),
          h('select', {
            style: S.input,
            value: draft?.language ?? 'zh',
            onChange: (event) => setDraft({ ...draft, language: event.target.value }),
          },
          h('option', { value: 'zh' }, '中文'),
          h('option', { value: 'en' }, 'English'))),
        h('div', { style: S.row }, h('div', { style: S.label }, t('groups')),
          h('input', {
            type: 'checkbox',
            checked: draft?.groups !== false,
            onChange: (event) => setDraft({ ...draft, groups: event.target.checked }),
          })),
        h('div', { style: S.actions },
          h('button', {
            type: 'button',
            style: S.button,
            disabled: busy !== '' || !draft,
            onClick: () => run('save', () => post(SETTINGS, { global: draft })),
          }, busy === 'save' ? t('busy') : t('save')),
          h('span', { style: S.caption }, `${t('process')}: ${config.persona || '—'} / ${config.timezone || 'system'} / ${config.language}`)))

      const personaOptions = Array.isArray(data.personas) ? data.personas : []
      const knownPersona = personaDraft?.id && personaOptions.some((item) => item.id === personaDraft.id)
      const personaCard = h('div', { style: S.card },
        h('div', { style: S.head }, t('personaEditor')),
        h('div', { style: S.caption }, t('personaFormat')),
        h('div', { style: S.row }, h('div', { style: S.label }, t('persona')),
          h('select', {
            style: { ...S.input, width: 220 },
            value: personaDraft?.id ?? '',
            onChange: (event) => {
              if (!event.target.value) newPersona()
              else openPersona(event.target.value)
            },
          },
          h('option', { value: '' }, t('personaNew')),
          ...personaOptions.map((persona) => h('option', { key: persona.id, value: persona.id }, persona.name || persona.id)),
          knownPersona || !personaDraft?.id
            ? null
            : h('option', { key: personaDraft.id, value: personaDraft.id }, personaDraft.name || personaDraft.id)),
          h('button', {
            type: 'button',
            style: S.button,
            disabled: personaBusy !== '',
            onClick: newPersona,
          }, t('personaNew'))),
        h('div', { style: S.row }, h('div', { style: S.label }, t('personaId')),
          h('input', {
            style: { ...S.input, width: 220 },
            value: personaDraft?.id ?? '',
            placeholder: 'jadekaninchen',
            disabled: !personaCreating || personaBusy !== '',
            onChange: (event) => setPersonaDraft({ ...personaDraft, id: event.target.value }),
          })),
        h('div', { style: S.row }, h('div', { style: S.label }, t('personaName')),
          h('input', {
            style: { ...S.input, width: 320 },
            value: personaDraft?.name ?? '',
            disabled: !personaDraft || personaBusy !== '',
            onChange: (event) => setPersonaDraft({ ...personaDraft, name: event.target.value }),
          })),
        h('div', { style: S.row }, h('div', { style: S.label }, t('personaDescription')),
          h('input', {
            style: { ...S.input, width: 420 },
            value: personaDraft?.description ?? '',
            disabled: !personaDraft || personaBusy !== '',
            onChange: (event) => setPersonaDraft({ ...personaDraft, description: event.target.value }),
          })),
        h('div', { style: S.row }, h('div', { style: S.label }, t('personaTags')),
          h('input', {
            style: { ...S.input, width: 420 },
            value: personaDraft?.tags ?? '',
            placeholder: '标签1, 标签2',
            disabled: !personaDraft || personaBusy !== '',
            onChange: (event) => setPersonaDraft({ ...personaDraft, tags: event.target.value }),
          })),
        h('div', { style: { display: 'grid', gap: 6 } },
          h('div', { style: S.label }, t('personaBody')),
          h('textarea', {
            style: S.textarea,
            value: personaDraft?.body ?? '',
            disabled: !personaDraft || personaBusy !== '',
            onChange: (event) => setPersonaDraft({ ...personaDraft, body: event.target.value }),
          })),
        h('div', { style: S.actions },
          h('button', {
            type: 'button',
            style: S.button,
            disabled: personaBusy !== '' || !personaDraft,
            onClick: savePersona,
          }, personaBusy === 'save' ? t('busy') : t('personaSave')),
          h('button', {
            type: 'button',
            style: S.button,
            disabled: personaBusy !== '' || !personaDraft,
            onClick: () => setPersonaDraft({ ...personaDraft, body: BODY_TEMPLATE }),
          }, t('personaTemplate')),
          h('button', {
            type: 'button',
            style: S.button,
            disabled: personaBusy !== '' || !personaDraft?.id || personaDraft.id === config.persona,
            onClick: deletePersona,
          }, personaBusy === 'delete' ? t('busy') : t('personaDelete')),
          personaNotice ? h('span', { style: S.notice }, personaNotice) : null),
        personaError ? h('div', { style: S.error }, personaError) : null)

      const items = conversations.length === 0
        ? [h('div', { style: S.caption }, t('empty'))]
        : conversations.map((item) => {
          const gate = item.gate || {}
          const open = editing === item.conversation
          const current = gateDraft[item.conversation] ?? {
            idleMinutes: gate.idleMinutes,
            maxPerHour: gate.maxPerHour,
            quietHours: gate.quietHours,
            enabled: gate.enabled,
          }
          return h('div', { key: item.conversation, style: S.item },
            h('div', { style: S.itemRow },
              h('div', { style: S.itemTitle }, item.title || item.conversation),
              h('span', { style: S.badge }, item.live ? t('live') : t('cold')),
              item.unread > 0 ? h('span', { style: S.badge }, fill(t('unread'), { count: item.unread })) : null,
              item.dropped > 0 ? h('span', { style: S.badge }, fill(t('dropped'), { count: item.dropped })) : null,
              h('span', { style: S.caption }, `${t('lastActivity')} ${when(item.lastActivity)}`),
              h('button', {
                type: 'button',
                style: S.button,
                onClick: () => setEditing(open ? '' : item.conversation),
              }, open ? t('close') : t('edit'))),
            open ? h('div', { style: S.actions },
              h('span', { style: S.caption }, t('gate')),
              h('label', { style: S.caption }, t('idle')),
              h('input', {
                style: S.input,
                type: 'number',
                min: 1,
                value: current.idleMinutes,
                onChange: (event) => setGateDraft({
                  ...gateDraft,
                  [item.conversation]: { ...current, idleMinutes: event.target.value },
                }),
              }),
              h('label', { style: S.caption }, t('perHour')),
              h('input', {
                style: S.input,
                type: 'number',
                min: 1,
                value: current.maxPerHour,
                onChange: (event) => setGateDraft({
                  ...gateDraft,
                  [item.conversation]: { ...current, maxPerHour: event.target.value },
                }),
              }),
              h('label', { style: S.caption }, t('quiet')),
              h('input', {
                style: S.input,
                value: current.quietHours ?? '',
                placeholder: '23:00-08:00',
                onChange: (event) => setGateDraft({
                  ...gateDraft,
                  [item.conversation]: { ...current, quietHours: event.target.value },
                }),
              }),
              h('label', { style: S.caption },
                h('input', {
                  type: 'checkbox',
                  checked: current.enabled !== false,
                  onChange: (event) => setGateDraft({
                    ...gateDraft,
                    [item.conversation]: { ...current, enabled: event.target.checked },
                  }),
                }), ` ${t('gate')}`),
              h('button', {
                type: 'button',
                style: S.button,
                disabled: busy !== '',
                onClick: () => run('gate', () => post(SETTINGS, {
                  gate: { conversation: item.conversation, ...current },
                }).then((result) => {
                  setEditing('')
                  return result
                })),
              }, busy === 'gate' ? t('busy') : t('save')),
              h('button', {
                type: 'button',
                style: S.button,
                disabled: busy !== '',
                onClick: () => run('gate', () => post(SETTINGS, {
                  gate: { conversation: item.conversation },
                }).then((result) => {
                  setEditing('')
                  return result
                })),
              }, t('reset'))) : null)
        })

      return h('div', { style: S.page },
        header,
        error ? h('div', { style: S.error }, error) : null,
        notice ? h('div', { style: S.notice }, notice) : null,
        bridgeCard,
        settingsCard,
        personaCard,
        h('div', { style: { display: 'grid', gap: 10 } },
          h('div', { style: S.head }, t('conversations')),
          h('div', { style: S.list }, items)))
    }

    return {
      inject: ['slots', 'locale'],
      apply(ctx) {
        ctx.effect(() => ctx.locale.register(NS, 'en', DICTS.en), 'jadekaninchen: en dictionary')
        ctx.effect(() => ctx.locale.register(NS, 'zh', DICTS.zh), 'jadekaninchen: zh dictionary')
        const t = ctx.locale.bind(NS)
        boundT = t

        ctx.slots.inject('sidebar.panellist', () => ctx.slots.register({
          name: 'sidebar.panellist',
          id: PANEL_ID,
          order: 5,
          label: () => t('panel'),
          locale: NS,
        }, Icon))

        ctx.slots.inject('main', () => ctx.slots.register({
          name: 'main',
          key: PANEL_ID,
          locale: NS,
        }, PanelPage))
      },
    }
  },
})
