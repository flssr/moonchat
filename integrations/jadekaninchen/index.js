// Jadekaninchen：MondChat ⇄ DSH 的装配层，只做三件事——建服务、提供给别的插件、挂路由。
// 业务在 src/service.js，协议在 src/bridge/，视图在 client.js。
//
// 设计前提（与本仓库 docs 一致）：
//   · 平台不替你筛消息，agent 收该账号能看到的全部会话；筛选在应用侧（这里）。
//   · 桥是 OneBot 12 实现（integrations/onebot），插件只是它的一个应用端。
//   · 每个 MondChat 私聊/群对应一个 DSH 会话；会话的权限预设统一压到只读。
//   · 不回复 = 不调 mondchat_send，不用哨兵文本，也没有自动转发。

import { registerRoutes } from './src/routes.js'
import { MondChatService } from './src/service.js'

export { inQuietHours } from './src/model/settings.js'

export const name = 'jadekaninchen'
export const inject = ['tools', 'sessions', 'sessionController']

export function apply(ctx, config = {}) {
  const runtime = createRuntime(ctx, config)
  // 服务暴露给别的插件用：ctx.get('mondchat').status() 之类。
  ctx.effect(() => {
    ctx.provide?.('mondchat', runtime.service)
    return () => {}
  })
  runtime.start()
  return runtime
}

export function createRuntime(ctx, config = {}, deps = {}) {
  const log = (...args) => console.log('[jadekaninchen]', ...args)
  const service = new MondChatService({ ctx, config, deps, log })

  return {
    service,
    start() {
      ctx.effect(() => {
        service.start()
        return () => service.dispose()
      }, 'jadekaninchen: service')
      registerRoutes(ctx, service, { log })
    },
    ingest: (event) => service.ingest(event),
    tick: (now) => service.tick(now),
    ensureSession: (conversation) => service.ensureSession(conversation),
    status: () => service.status(),
    get conversations() {
      return service.conversations
    },
    get state() {
      return service.state
    },
    get settings() {
      return { global: service.global, overrides: service.overrides }
    },
  }
}
