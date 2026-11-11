// 最小 agent 示例端点：不监听任何端口，只做三件事——换 Turms 凭据、连 /im、收到消息回一句。
//
// 它演示的是 docs/agent-connection.md 的接入面，不是新接口：
//   ① 用归属者给的账号密钥 POST /api/sessions 换 Turms 凭据（与真人切账号同一条签发路径）
//   ② 用这份凭据连 turms-gateway 收该账号的全部会话推送
//   ③ 发言走 Biz 的唯一写入口 POST /api/conversations/{type}/{id}/messages
//
// 平台不替它筛会话：收到什么由它自己判断（这里只做一个回声，够验链路）。
//
// 前置：Biz 与 Turms 都在跑，且归属者已经建好 agent 账号、拿到一次性密钥。
// 跑法：
//   cd infra/turms/smoke && npm i
//   $env:MOONCHAT_ACCOUNT_KEY='<一次性密钥>'; $env:MOONCHAT_API_BASE='http://localhost:8080'
//   node agent-example.mjs
//
// 可用环境变量：MOONCHAT_API_BASE（默认 http://localhost:8080）、MOONCHAT_ACCOUNT_KEY（必填）、
//              MOONCHAT_REPLY_PREFIX（默认「收到：」）、MOONCHAT_DEVICE_TYPE（默认 browser，小写；

import TurmsClient from 'turms-client-js';

const API_BASE = (process.env.MOONCHAT_API_BASE ?? 'http://localhost:8080').replace(/\/+$/, '');
const ACCOUNT_KEY = process.env.MOONCHAT_ACCOUNT_KEY;
const REPLY_PREFIX = process.env.MOONCHAT_REPLY_PREFIX ?? '收到：';
// X-Device-Type 只认小写（desktop/browser/ios/android/others）；Turms 的 DeviceType 是它的大写形式。
const DEVICE_TYPE = process.env.MOONCHAT_DEVICE_TYPE ?? 'browser';

if (!ACCOUNT_KEY) {
    console.error('缺少 MOONCHAT_ACCOUNT_KEY：归属者创建 agent 时那串一次性密钥');
    process.exit(2);
}

function wsUrl(gatewayUrl) {
    if (gatewayUrl.startsWith('ws://') || gatewayUrl.startsWith('wss://')) {
        return gatewayUrl;
    }
    if (gatewayUrl.startsWith('https://')) {
        return `wss://${gatewayUrl.slice('https://'.length)}`;
    }
    return `ws://${gatewayUrl.replace(/^http:\/\//, '')}`;
}

// ① 换凭据：这一步就是 agent 与真人的唯一差别（入口凭据不同，签出来的东西一样）。
let sessionRes;
try {
    sessionRes = await fetch(`${API_BASE}/api/sessions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ account_key: ACCOUNT_KEY }),
    });
} catch (e) {
    console.error(`换凭据失败：连不上 ${API_BASE}（${e.message}）`);
    process.exit(1);
}
if (!sessionRes.ok) {
    const body = await sessionRes.text();
    console.error(`换凭据失败 ${sessionRes.status}: ${body}`);
    process.exit(1);
}
const session = await sessionRes.json();
const myId = String(session.turms.user_id);
console.log(`已换到凭据：账号 ${session.account_id}（${session.display_name}），网关 ${session.turms.gateway_url}`);

// ② 连 /im：拿到的 JWT 只授 QUERY，所以只能收与查，发不出消息。
const client = new TurmsClient({ wsUrl: wsUrl(session.turms.gateway_url) });
await client.userService.login({
    userId: myId,
    password: session.turms.credential,
    deviceType: DEVICE_TYPE.toUpperCase(),
});
console.log('已连上 /im，等消息（Ctrl+C 退出）');

// 凭据 12 小时过期：agent 自己负责在到期前重换，否则首次重连就带着死 JWT 登不进去。
let credential = session.turms.credential;
async function renew() {
    const res = await fetch(`${API_BASE}/api/sessions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ account_key: ACCOUNT_KEY }),
    });
    if (!res.ok) {
        console.error(`续期失败 ${res.status}: ${await res.text()}`);
        return;
    }
    const fresh = await res.json();
    credential = fresh.turms.credential;
    console.log('Turms 凭据已续期');
}
const expiresAt = Date.parse(session.expires_at ?? '');
if (Number.isFinite(expiresAt)) {
    const lead = Math.max(expiresAt - Date.now() - 30 * 60 * 1000, 60 * 1000);
    setInterval(renew, lead).unref();
}

// ③ 收到一条就回一句：发言走写入网关，不经过自己的 Turms 会话。
client.messageService.addMessageListener(async (message) => {
    // 整段包住：这个回调 reject 会以未处理拒绝结束整个长驻进程。
    try {
        const senderId = String(message.senderId ?? '');
        const text = message.text ?? '';
        // 自己的发言也会推回来，别回声成环；没有发送者或内容的通知直接忽略。
        if (!senderId || !text || senderId === myId) {
            return;
        }
        const isGroup = message.groupId !== null && message.groupId !== undefined;
        const type = isGroup ? 'room' : 'dm';
        const targetId = isGroup ? message.groupId : senderId;

        console.log(`收到 ${isGroup ? `群 ${targetId}` : `私聊 ${senderId}`}：${text}`);
        // 写入网关正文上限 500：入向可能已经 500 字，带上前缀就超了。
        const reply = `${REPLY_PREFIX}${text}`.slice(0, 500);
        const replyRes = await fetch(`${API_BASE}/api/conversations/${type}/${targetId}/messages`, {
            method: 'POST',
            headers: {
                'content-type': 'application/json',
                // 用账号密钥当凭据：来源会被记成 agent，并进「账号 → 会话」两级桶。
                authorization: `Bearer ${ACCOUNT_KEY}`,
                'x-device-type': DEVICE_TYPE,
            },
            body: JSON.stringify({ text: reply }),
        });
        if (!replyRes.ok) {
            console.error(`回话失败 ${replyRes.status}: ${await replyRes.text()}`);
            return;
        }
        const sent = await replyRes.json();
        console.log(`已回话 message_id=${sent.message_id}`);
    } catch (e) {
        console.error(`处理消息失败：${e.message}`);
    }
});

for (const sig of ['SIGINT', 'SIGTERM']) {
    process.on(sig, async () => {
        await client.close();
        process.exit(0);
    });
}
