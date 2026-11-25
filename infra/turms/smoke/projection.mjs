// 投影关系写入的冒烟：需要一个跑着的 Biz(8080，投影已打开) + 真 Turms(8510)。
//
// 专防 2026-11-22 那类错：客户端把 Admin 关系路径写成 `/relationships`（真路径是
// `/users/relationships`），假 Turms Admin 按「方法+路径」分派、两边自洽，单测全绿但真机上
// 对账每次 400、存量投影一条也补不出来。这里全部打在真 Turms 上：
//   1. Biz 写路径建好友 → 派发器把两条方向行写进 Turms（establishmentDate 有值、blockDate 空）
//   2. 直接从 Turms 删掉这两行 → 对账把缺失的行补回来（再派发一次）
//   3. 补回来后形状不变，且每个方向只有一行（对账没有重复写入）
//
// 前置：
//   1) Biz 以投影打开 + 短对账周期启动（周期默认 03:00，冒烟等不起）：
//        MONDCHAT_PROJECTION_ENABLED=true \
//        MONDCHAT_PROJECTION_RECONCILE_CRON='*/20 * * * * *' <启动 biz>
//   2) Turms 栈起来（见 smoke.mjs 头部的三份 compose）
//   3) cd infra/turms/smoke && npm i && npm run projection
//
// 环境变量：MONDCHAT_API_BASE（默认 http://localhost:8080）、TURMS_ADMIN_URL（默认
// http://localhost:8510）、TURMS_ADMIN_USER / TURMS_ADMIN_PASSWORD（默认 turms/turms）、
// PROJECTION_DISPATCH_TIMEOUT_MS（默认 30000）、PROJECTION_RECONCILE_TIMEOUT_MS（默认 120000）。
import crypto from 'node:crypto';

const API = (process.env.MONDCHAT_API_BASE ?? 'http://localhost:8080').replace(/\/+$/, '');
const ADMIN_URL = (process.env.TURMS_ADMIN_URL ?? 'http://localhost:8510').replace(/\/+$/, '');
const ADMIN_USER = process.env.TURMS_ADMIN_USER ?? 'turms';
const ADMIN_PASSWORD = process.env.TURMS_ADMIN_PASSWORD ?? 'turms';
const DISPATCH_TIMEOUT = Number(process.env.PROJECTION_DISPATCH_TIMEOUT_MS ?? 30_000);
// 对账是 cron，默认周期 20 秒；给足两轮再加余量。
const RECONCILE_TIMEOUT = Number(process.env.PROJECTION_RECONCILE_TIMEOUT_MS ?? 120_000);
// 随机后缀：重跑不撞 email_taken。
const run = crypto.randomBytes(6).toString('hex');

const results = [];
function check(name, ok, detail = '') {
    results.push({ name, ok });
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
}

function require(ok, what, detail = '') {
    if (!ok) {
        console.error(`前置失败：${what}${detail ? '  ' + detail : ''}`);
        process.exit(1);
    }
}

async function request(method, path, body, token) {
    const res = await fetch(API + path, {
        method,
        headers: {
            'content-type': 'application/json',
            ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        body: method === 'GET' ? undefined : JSON.stringify(body ?? {}),
    });
    const text = await res.text();
    let json;
    try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
    return { status: res.status, json };
}
const post = (path, body, token) => request('POST', path, body, token);

async function admin(method, path) {
    const basic = Buffer.from(`${ADMIN_USER}:${ADMIN_PASSWORD}`).toString('base64');
    const res = await fetch(`${ADMIN_URL}${path}`, {
        method,
        headers: { Authorization: `Basic ${basic}`, 'Content-Type': 'application/json' },
    });
    const text = await res.text();
    if (!res.ok) {
        throw new Error(`${method} ${path} → ${res.status} ${text}`);
    }
    return text ? JSON.parse(text) : {};
}

/** 这一方向上 Turms 里的那一行（没有就返回 null）。 */
async function relationshipRow(ownerId, relatedUserId) {
    const body = await admin('GET',
        `/users/relationships?ownerIds=${ownerId}&relatedUserIds=${relatedUserId}&size=10`);
    const rows = Array.isArray(body?.data) ? body.data : [];
    // 只认 key 完全对上的行：Admin 的 ownerIds 过滤之外，别让同一 owner 的其他关系混进来。
    const matched = rows.filter((row) =>
        String(row?.key?.ownerId) === String(ownerId)
        && String(row?.key?.relatedUserId) === String(relatedUserId));
    return { matched, row: matched[0] ?? null };
}

/** 行形状：好友必须有 establishmentDate，且 blockDate 为空。 */
function friendshipShape(row) {
    if (!row) {
        return 'missing';
    }
    const hasEstablishment = Boolean(row.establishmentDate);
    const noBlock = row.blockDate === undefined || row.blockDate === null;
    return hasEstablishment && noBlock ? 'ok' : `establishmentDate=${row.establishmentDate} blockDate=${row.blockDate}`;
}

async function waitFor(what, predicate, timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const value = await predicate();
        if (value) {
            return value;
        }
        await new Promise((r) => setTimeout(r, 500));
    }
    console.error(`等待超时：${what}`);
    return null;
}

// ① 两个真人账号（走 Biz 的公开注册，顺带产生 account.created 事件）
const a = await post('/api/auth/register', { email: `pa${run}@test.local`, password: 'password1', display_name: '投影甲' });
const b = await post('/api/auth/register', { email: `pb${run}@test.local`, password: 'password1', display_name: '投影乙' });
check('注册两个账号', a.status === 201 && b.status === 201, `a=${a.status} b=${b.status}`);
require(a.status === 201 && b.status === 201, '注册', `a=${a.status} b=${b.status} ${a.json.code ?? ''}${b.json.code ?? ''}`);
const A = a.json.account_id;
const B = b.json.account_id;

const la = await post('/api/auth/login', { email: `pa${run}@test.local`, password: 'password1' });
const lb = await post('/api/auth/login', { email: `pb${run}@test.local`, password: 'password1' });
require(la.status === 200 && lb.status === 200, '登录', `a=${la.status} b=${lb.status}`);
const tokenA = la.json.token;
const tokenB = lb.json.token;

// ② Biz 写路径建好友：A 申请，B 同意（同事务写 friendship.changed 事件）
const req = await post('/api/friendships', { peer_account_id: B }, tokenA);
const acc = await post(`/api/friendships/${A}`, { action: 'accept' }, tokenB);
check('好友申请与同意', req.status === 201 && acc.status === 200, `req=${req.status} accept=${acc.status}`);
require(req.status === 201 && acc.status === 200, '加好友', `req=${req.status} accept=${acc.status}`);

// ③ 派发器把两个方向的行写进真 Turms（路径写错的话这里会 400，check 直接失败）
const dispatched = await waitFor('派发到 Turms', async () => {
    const ab = await relationshipRow(A, B);
    const ba = await relationshipRow(B, A);
    return ab.row && ba.row ? { ab, ba } : null;
}, DISPATCH_TIMEOUT);
check('派发后 A→B 的行在 Turms 里', Boolean(dispatched), dispatched ? '' : '超时（Biz 是否 MONDCHAT_PROJECTION_ENABLED=true？）');
check('派发后 B→A 的行在 Turms 里', Boolean(dispatched));
if (dispatched) {
    check('A→B 行形状（有 establishmentDate、无 blockDate）', friendshipShape(dispatched.ab.row) === 'ok', friendshipShape(dispatched.ab.row));
    check('B→A 行形状（有 establishmentDate、无 blockDate）', friendshipShape(dispatched.ba.row) === 'ok', friendshipShape(dispatched.ba.row));
}

// ④ 从 Turms 直接删掉这两行：模拟「投影缺行」（就是路径写错时的现场）
await admin('DELETE',
    `/users/relationships?keys[0].ownerId=${A}&keys[0].relatedUserId=${B}`
    + `&keys[1].ownerId=${B}&keys[1].relatedUserId=${A}`);
const afterDelete = await relationshipRow(A, B);
check('删行后 Turms 确实没有该关系', afterDelete.row === null, `rows=${afterDelete.matched.length}`);

// ⑤ 对账把缺的行补回来（cron 周期决定等待时间；默认 20 秒一轮）
const reconciled = await waitFor('对账补回关系', async () => {
    const ab = await relationshipRow(A, B);
    const ba = await relationshipRow(B, A);
    return ab.row && ba.row ? { ab, ba } : null;
}, RECONCILE_TIMEOUT);
check('对账把 A→B 的行补回来了', Boolean(reconciled),
    reconciled ? '' : '超时（MONDCHAT_PROJECTION_RECONCILE_CRON 是否改成了短周期？）');
if (reconciled) {
    check('对账补回 B→A 的行', Boolean(reconciled.ba));
    check('补回的 A→B 形状不变', friendshipShape(reconciled.ab.row) === 'ok', friendshipShape(reconciled.ab.row));
    check('补回的 B→A 形状不变', friendshipShape(reconciled.ba.row) === 'ok', friendshipShape(reconciled.ba.row));
    check('每个方向只有一行（对账没重复写）',
        reconciled.ab.matched.length === 1 && reconciled.ba.matched.length === 1,
        `A→B=${reconciled.ab.matched.length} B→A=${reconciled.ba.matched.length}`);
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} 项通过`);
process.exit(failed.length === 0 ? 0 : 1);
