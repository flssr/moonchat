// 面板用的 HTTP 路由：只做协议转换，把请求交给 service。
// 路由注册进宿主的共享 /api 通道（与其它插件同一套会话鉴权），不自己起服务器。

const STATUS_PATH = '/api/mondchat/status'
const BRIDGE_PATH = '/api/mondchat/bridge'
const SETTINGS_PATH = '/api/mondchat/settings'
const PERSONAS_PATH = '/api/mondchat/personas'

const json = (body, status = 200) => new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
})

const readBody = async (request) => {
    try {
        return await request.json()
    } catch {
        return {}
    }
}

/** 注册插件路由；没有 connection 服务的环境（比如自检）就什么也不做。 */
export function registerRoutes(ctx, service, { log = () => {} } = {}) {
    const connection = ctx.get('connection')
    if (!connection?.fetch?.register) return

    const register = (path, methods, handler) => {
        ctx.effect(() => connection.fetch.register({
            path,
            methods,
            requestBody: 'buffered',
            fetch: handler,
        }), `mondchat: ${path}`)
    }

    register(STATUS_PATH, ['GET'], async () => {
        try {
            return json(service.status())
        } catch (error) {
            log('读取状态失败：', error.message)
            return json({ error: String(error.message ?? error) }, 500)
        }
    })

    register(BRIDGE_PATH, ['POST'], async (request) => {
        const body = await readBody(request)
        try {
            if (body.action === 'start') {
                await service.startBridge()
            } else if (body.action === 'stop') {
                await service.stopBridge()
            } else if (body.action !== 'restart') {
                return json({ error: 'action 只能是 start / stop / restart' }, 400)
            } else {
                await service.restartBridge()
            }
            return json({ bridge: service.status().bridge })
        } catch (error) {
            log('桥操作失败：', error.message)
            return json({ error: String(error.message ?? error) }, 400)
        }
    })

    register(PERSONAS_PATH, ['POST'], async (request) => {
        const body = await readBody(request)
        try {
            if (body.action === 'read') {
                const persona = service.personaDetails(body.id)
                if (!persona) return json({ error: '人格不存在' }, 404)
                return json({ persona, template: service.personas.template })
            }
            if (body.action === 'save') {
                return json({
                    ...service.savePersona({
                        id: body.id,
                        name: body.name,
                        description: body.description,
                        tags: body.tags,
                        body: body.body,
                    }),
                    template: service.personas.template,
                })
            }
            if (body.action === 'delete') {
                return json(service.deletePersona(body.id))
            }
            if (body.action === 'template') {
                return json({ template: service.personas.template })
            }
            return json({ error: 'action 只能是 read / save / delete / template' }, 400)
        } catch (error) {
            log('人格操作失败：', error.message)
            return json({ error: String(error.message ?? error) }, 400)
        }
    })

    register(SETTINGS_PATH, ['POST'], async (request) => {
        const body = await readBody(request)
        try {
            const view = { bridge: service.status().bridge }
            if (body.global && typeof body.global === 'object') {
                view.global = await service.setGlobal(body.global)
                // 全局项写回 patch 后会重装插件，这里只确认已受理。
                view.reload = true
            }
            if (body.gate && typeof body.gate === 'object' && body.gate.conversation) {
                const { conversation, ...patch } = body.gate
                view.gate = service.setGate(String(conversation), patch)
            }
            if (view.global === undefined && view.gate === undefined) {
                return json({ error: '要么给 global，要么给 gate' }, 400)
            }
            return json(view)
        } catch (error) {
            log('改设置失败：', error.message)
            return json({ error: String(error.message ?? error) }, 400)
        }
    })
}
