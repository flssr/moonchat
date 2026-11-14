// S1 身份底座的端到端判据：跑在「真 Turms + 真 Biz + 真 PG」上，验 S1 的四条片末判据：
//   1. 注册 → 登录 → POST /api/sessions → turms-client-js 用这份凭据登录 /im
//   2. account.id 就是 Turms 用户 id（从 Turms 那侧用 Admin API 核对，不只看 Biz 的回包）
//   3. QUERY-only 凭据发不出消息（CREATE_MESSAGE_REQUEST → UNAUTHORIZED_REQUEST 1106）
//   4. 续期后还是同一个账号
//
// 前置：
//   1) Turms 按 README 的冒烟步骤起来（含 jwt-identity 覆盖与共享密钥文件）
//   2) Biz 跑起来，并且与 Turms 用同一份 MONDCHAT_JWT_SECRET_FILE（还要给 PG 与登录密钥）：
//        $env:SPRING_DATASOURCE_URL = 'jdbc:postgresql://localhost:15432/mondchat'
//        $env:SPRING_DATASOURCE_USERNAME = 'mondchat'
//        $env:SPRING_DATASOURCE_PASSWORD = 'mondchat'
//        $env:MONDCHAT_JWT_SECRET_FILE = "$PWD/infra/turms/secrets/jwt-hmac256.key"
//        $env:MONDCHAT_AUTH_JWT_SECRET  = '<32 字节以上的任意字符串>'
//        .\backend\mvnw.cmd -f backend\pom.xml -pl mondchat-biz spring-boot:run
//   3) cd infra/turms/smoke; npm run identity
//
// 可用环境变量覆盖：MONDCHAT_BIZ_URL / TURMS_ADMIN_URL / TURMS_ADMIN_USER /
// TURMS_ADMIN_PASSWORD / TURMS_WS_URL
//
// 脚本不清理它建的东西：V1 没有删账号的能力，所以每次运行会留下一个账号行与一个 Turms 用户。
// 前置里的 PG 也是这个道理——接口测试用 Testcontainers 临时库，这里要一个长期存在的库。
// 由此有一个坑：只重建 PG 而不动 Turms，账号 id 会重放、撞上 Turms 里残留的同 id 用户，注册返回 503；
// 要么别重建 PG，要么先把 Turms 里对应 id 的用户删掉（DELETE /users?ids=<id>&deleteLogically=false）。

import crypto from 'node:crypto';
import TurmsClient from 'turms-client-js';

const BIZ_URL = process.env.MONDCHAT_BIZ_URL ?? 'http://localhost:8080';
const ADMIN_URL = process.env.TURMS_ADMIN_URL ?? 'http://localhost:8510';
const ADMIN_USER = process.env.TURMS_ADMIN_USER ?? 'turms';
const ADMIN_PASSWORD = process.env.TURMS_ADMIN_PASSWORD ?? 'turms';
const WS_URL_OVERRIDE = process.env.TURMS_WS_URL;
const TIMEOUT_MS = 30_000;

const results = [];

function check(name, ok, detail = '') {
    results.push({ name, ok });
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

async function api(method, path, { token, body } = {}) {
    const headers = {};
    if (body !== undefined) {
        headers['Content-Type'] = 'application/json';
    }
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const response = await fetch(`${BIZ_URL}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    return { status: response.status, json: text ? JSON.parse(text) : {} };
}

async function admin(path) {
    const basic = Buffer.from(`${ADMIN_USER}:${ADMIN_PASSWORD}`).toString('base64');
    const response = await fetch(`${ADMIN_URL}${path}`, {
        headers: { Authorization: `Basic ${basic}` },
    });
    const text = await response.text();
    if (!response.ok) {
        throw new Error(`GET ${path} → ${response.status} ${text}`);
    }
    return text ? JSON.parse(text) : {};
}

function withTimeout(promise, label) {
    return Promise.race([
        promise,
        new Promise((_, reject) => setTimeout(() => reject(new Error(`超时：${label}`)), TIMEOUT_MS)),
    ]);
}

async function main() {
    const email = `e2e-${crypto.randomBytes(6).toString('hex')}@example.com`;
    const password = 'secret123';
    console.log(`Biz：${BIZ_URL}`);

    // 1. 注册：不签发凭据，只落账号并建 Turms 用户
    const registered = await api('POST', '/api/auth/register', {
        body: { email, password, display_name: 'E2E 身份' },
    });
    const accountId = registered.json?.account_id;
    check('注册返回 201 与账号 id', registered.status === 201 && Number.isInteger(accountId),
        `status=${registered.status} accountId=${accountId}`);
    if (!Number.isInteger(accountId)) {
        throw new Error(`注册没拿到账号 id：${JSON.stringify(registered.json)}`);
    }

    // 2. 从 Turms 那侧核对 account.id 就是 Turms 用户 id
    const turmsUsers = await admin(`/users?ids=${accountId}`);
    const turmsUser = turmsUsers?.data?.[0];
    check('Turms 里就有这个 id 的用户（account.id == Turms userId）', turmsUser?.id === accountId,
        `turmsUserId=${turmsUser?.id} name=${turmsUser?.name}`);

    // 3. 登录拿登录 JWT
    const loggedIn = await api('POST', '/api/auth/login', { body: { email, password } });
    const token = loggedIn.json?.token;
    check('登录返回登录 JWT', loggedIn.status === 200 && typeof token === 'string',
        `status=${loggedIn.status} expiresAt=${loggedIn.json?.expires_at}`);
    if (!token) {
        throw new Error(`登录没拿到 token：${JSON.stringify(loggedIn.json)}`);
    }

    // 4. 换 Turms 凭据
    const session = await api('POST', '/api/sessions', { token, body: { account_id: accountId } });
    const credential = session.json?.turms?.credential;
    const gatewayUrl = WS_URL_OVERRIDE ?? session.json?.turms?.gateway_url;
    check('换到 Turms 凭据且 user_id 就是 account_id',
        session.status === 200 && session.json?.turms?.user_id === accountId && typeof credential === 'string',
        `status=${session.status} user_id=${session.json?.turms?.user_id} gateway=${gatewayUrl}`);
    if (!credential) {
        throw new Error(`没拿到 Turms 凭据：${JSON.stringify(session.json)}`);
    }

    // 5. 用这份凭据登录 /im
    const client = new TurmsClient({ wsUrl: gatewayUrl });
    await withTimeout(client.userService.login({
        userId: String(accountId),
        password: credential,
        deviceType: 'DESKTOP',
    }), '用 Biz 签的凭据登录 /im');
    check('Biz 签的凭据能登录 /im', true, `user ${accountId}`);

    // 6. 同一份凭据发不出消息：客户端没有写入权限
    let sendRejected = false;
    let sendDetail = '';
    try {
        await withTimeout(client.messageService.sendMessage({
            isGroupMessage: false,
            targetId: String(accountId + 1),
            text: 'identity: this must be rejected',
        }), '客户端尝试直连 Turms 发消息');
        sendDetail = '未被拒绝（说明 statements 没生效）';
    } catch (error) {
        const code = error?.code ?? Number((/:([0-9]+):/.exec(error?.message ?? '') || [])[1]);
        sendRejected = code === 1106;
        sendDetail = `code=${code}`;
    }
    check('QUERY-only 凭据发不出消息（1106）', sendRejected, sendDetail);

    // 7. 续期：仍是同一个账号
    const refreshed = await api('POST', '/api/auth/refresh', { token });
    const newToken = refreshed.json?.token;
    const mine = await api('GET', '/api/accounts/mine', { token: newToken });
    const first = mine.json?.items?.[0];
    check('续期后仍是同一个账号',
        refreshed.status === 200 && typeof newToken === 'string'
        && refreshed.json?.account?.account_id === accountId
        && first?.account_id === accountId && first?.type === 'human',
        `refreshStatus=${refreshed.status} mineFirst=${first?.account_id} type=${first?.type}`);

    await client.driver.close();

    const failed = results.filter((item) => !item.ok);
    console.log(`\n${results.length - failed.length}/${results.length} 通过`);
    process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((error) => {
    console.error(`身份链路失败：${error.stack ?? error.message}`);
    process.exit(1);
});
