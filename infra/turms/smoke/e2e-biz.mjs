// Biz 层端到端：需要一个跑着的 Biz(8080) + 真 Turms(20510)。
// 它验的是「客户端会把/应该会走的那几条链路」，与 smoke.mjs（只验 Turms 自己的边界）互补：
//   注册 → 登录 → 换 Turms 凭据 → 非好友私聊被拒 → 加好友 → 私聊推送
//   → 建群 → 拉人 → 群消息推送 → 资料页字段
//
// 跑法：cd infra/turms/smoke && npm i && node e2e-biz.mjs
// 环境变量：MOONCHAT_API_BASE（默认 http://localhost:8080）
import TurmsClient from 'turms-client-js';

const API = (process.env.MOONCHAT_API_BASE ?? 'http://localhost:8080').replace(/\/+$/, '');
const run = Date.now().toString().slice(-6);

async function post(path, body, token) {
    const res = await fetch(API + path, {
        method: 'POST',
        headers: {
            'content-type': 'application/json',
            ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body ?? {}),
    });
    const text = await res.text();
    let json;
    try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
    return { status: res.status, json };
}
async function get(path, token) {
    const res = await fetch(API + path, {
        headers: token ? { authorization: `Bearer ${token}` } : {},
    });
    const text = await res.text();
    return { status: res.status, json: text ? JSON.parse(text) : {} };
}

const results = [];
function check(name, ok, detail = '') {
    results.push({ name, ok });
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
}

// ① 注册两个真人账号
const a = await post('/api/auth/register', { email: `a${run}@test.local`, password: 'password1', display_name: '甲' });
const b = await post('/api/auth/register', { email: `b${run}@test.local`, password: 'password1', display_name: '乙' });
check('注册两个账号', a.status === 201 && b.status === 201, `a=${a.status} b=${b.status} id=${a.json.account_id}/${b.json.account_id}`);
const A = a.json.account_id, B = b.json.account_id;

// ② 登录
const la = await post('/api/auth/login', { email: `a${run}@test.local`, password: 'password1' });
const lb = await post('/api/auth/login', { email: `b${run}@test.local`, password: 'password1' });
check('两个账号都能登录', la.status === 200 && lb.status === 200);
const tokenA = la.json.token, tokenB = lb.json.token;

// ③ 换 Turms 凭据
const sa = await post('/api/sessions', { account_id: A }, tokenA);
const sb = await post('/api/sessions', { account_id: B }, tokenB);
check('换 Turms 凭据', sa.status === 200 && sb.status === 200,
    `gateway=${sa.json.turms?.gateway_url} ttl=${sa.json.expires_at}`);

// ④ 非好友私聊必须被拒（授权执行点在写入网关）
const deny = await post(`/api/conversations/dm/${B}/messages`, { text: '还没加好友就发' }, tokenA);
check('非好友私聊 403 not_friend', deny.status === 403 && deny.json.code === 'not_friend',
    `${deny.status} ${deny.json.code}`);

// ⑤ B 连上 Turms，等推送
const BClient = new TurmsClient({ wsUrl: sb.json.turms.gateway_url });
await BClient.userService.login({
    userId: String(B), password: sb.json.turms.credential, deviceType: 'DESKTOP',
});
const received = [];
BClient.messageService.addMessageListener((m) => {
    if (m.text && String(m.senderId) === String(A)) received.push(m.text);
});

// ⑥ 加好友：A 申请，B 同意
const req = await post('/api/friendships', { peer_account_id: B }, tokenA);
const acc = await post(`/api/friendships/${A}`, { action: 'accept' }, tokenB);
check('好友申请与同意', req.status === 201 && acc.status === 200,
    `req=${req.status} accept=${acc.status}`);

// ⑦ A 发私聊 → 201，B 收到推送
const send = await post(`/api/conversations/dm/${B}/messages`, { text: '真链路的第一条私聊' }, tokenA);
check('好友私聊 201', send.status === 201, `message_id=${send.json.message_id} sent_at=${send.json.sent_at}`);
await new Promise((r) => setTimeout(r, 2500));
check('B 通过 Turms 收到推送', received.includes('真链路的第一条私聊'), JSON.stringify(received));

// ⑧ 建群 → 拉 B → 发群消息 → B 收到
const room = await post('/api/rooms', { name: '真链路测试群' }, tokenA);
check('建群 201', room.status === 201, `room_id=${room.json.room_id}`);
const roomId = room.json.room_id;
const invite = await post(`/api/rooms/${roomId}/members`, { account_id: B }, tokenA);
check('拉人进群 201', invite.status === 201, `${invite.status}`);
await new Promise((r) => setTimeout(r, 1500));
const gsend = await post(`/api/conversations/room/${roomId}/messages`, { text: '群里的第一条' }, tokenA);
check('群消息 201', gsend.status === 201, `message_id=${gsend.json.message_id}`);
await new Promise((r) => setTimeout(r, 2500));
check('B 收到群消息推送', received.includes('群里的第一条'), JSON.stringify(received));

// ⑨ 资料页只返回三项
const prof = await get(`/api/accounts/${B}`, tokenA);
const keys = Object.keys(prof.json).sort().join(',');
check('资料页字段只有三样', keys === 'account_id,display_name,is_friend', keys);

await BClient.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} 项通过`);
process.exit(failed.length === 0 ? 0 : 1);
