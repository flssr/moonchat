// 面板用的 HTTP 路由：只做协议转换，把请求交给 service。
// 路由注册进宿主的共享 /api 通道（与其它插件同一套会话鉴权），不自己起服务器。

const STATUS_PATH = '/api/mondchat/status'

const json = (body, status = 200) => new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
})

/** 注册插件路由；没有 connection 服务的环境（比如自检）就什么也不做。 */
export function registerRoutes(ctx, service, { log = () => {} } = {}) {
    const connection = ctx.get('connection')
    if (!connection?.fetch?.register) return

    ctx.effect(() => connection.fetch.register({
        path: STATUS_PATH,
        methods: ['GET'],
        requestBody: 'buffered',
        fetch: async () => {
            try {
                return json(service.status())
            } catch (error) {
                log('读取状态失败：', error.message)
                return json({ error: String(error.message ?? error) }, 500)
            }
        },
    }), 'mondchat: status route')
}
