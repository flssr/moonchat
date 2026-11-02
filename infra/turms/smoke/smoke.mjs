// Turms 端到端冒烟：一次性验证脚本。
//
// 验证的是 docs/messaging-and-tunnel.md「凭据与客户端权限」一节的四条断言：
//   1. Admin API 能用指定 id 建用户（AddUserDTO.id）
//   2. Biz 用共享 HMAC 密钥签的 JWT 能登录 turms-gateway（gateway 的 type = jwt）
//   3. 只授 QUERY 的 JWT 发不出消息（CREATE_MESSAGE_REQUEST → UNAUTHORIZED_REQUEST，1106）
//   4. Admin API 能带 senderId 代发，消息真的投到目标账号的客户端会话
//
// 前置：
//   1) 生成密钥并把 gateway 切成 JWT 模式后启动 Turms：
//        docker compose -f vendor/turms/docker-compose.standalone.yml \
//          -f infra/turms/pinned-images.compose.yaml \
//          -f infra/turms/jwt-identity.compose.yaml up -d
//   2) 构建 vendored 客户端：cd vendor/turms/turms-client-js && npm i && npm run build
//   3) cd infra/turms/smoke && npm i && npm run smoke
//
// 可用环境变量覆盖：TURMS_ADMIN_URL / TURMS_WS_URL / TURMS_ADMIN_USER /
// TURMS_ADMIN_PASSWORD / MOONCHAT_JWT_SECRET_FILE

import fs from 'node:fs';
import path from 'node:path';
import jwt from 'jsonwebtoken';
import TurmsClient from 'turms-client-js';

const ADMIN_URL = process.env.TURMS_ADMIN_URL ?? 'http://localhost:8510';
const WS_URL = process.env.TURMS_WS_URL ?? 'ws://localhost:10510';
const ADMIN_USER = process.env.TURMS_ADMIN_USER ?? 'turms';
const ADMIN_PASSWORD = process.env.TURMS_ADMIN_PASSWORD ?? 'turms';
const SECRET_FILE = process.env.MOONCHAT_JWT_SECRET_FILE ?? path.join(import.meta.dirname, 'secrets', 'jwt-hmac256.key');
const USER_A = 9001;
const USER_B = 9002;
const TIMEOUT_MS = 20_000;

const results = [];
function check(name, ok, detail = '') {
    results.push({ name, ok });
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

function adminHeaders() {
    const basic = Buffer.from(`${ADMIN_USER}:${ADMIN_PASSWORD}`).toString('base64');
    return { Authorization: `Basic ${basic}`, 'Content-Type': 'application/json' };
}

async function admin(method, urlPath, body) {
    const response = await fetch(`${ADMIN_URL}${urlPath}`, {
        method,
        headers: adminHeaders(),
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    if (!response.ok) {
        throw new Error(`${method} ${urlPath} → ${response.status} ${text}`);
    }
    return text ? JSON.parse(text) : {};
}

function signTurmsJwt(secret, userId, ttl = '12h') {
    return jwt.sign(
        // Turms 只认 statements 里的策略；不给 statements 登录会直接失败
        { statements: [{ effect: 'ALLOW', actions: ['QUERY'], resources: ['*'] }] },
        secret,
        { algorithm: 'HS256', subject: String(userId), expiresIn: ttl },
    );
}

function withTimeout(promise, label) {
    return Promise.race([
        promise,
        new Promise((_, reject) => setTimeout(() => reject(new Error(`超时：${label}`)), TIMEOUT_MS)),
    ]);
}

async function main() {
    const secret = fs.readFileSync(SECRET_FILE);
    console.log(`密钥：${SECRET_FILE}（${secret.length} 字节）`);

    // 0. 清理上一次的冒烟账号，保证可重跑
    try {
        await admin('DELETE', `/users?ids=${USER_A}&ids=${USER_B}&deleteLogically=false`);
    } catch {
        // 首次运行不存在，忽略
    }

    // 1. 指定 id 建用户
    const createdA = await admin('POST', '/users', { id: USER_A, name: 'smoke-a', isActive: true });
    const createdB = await admin('POST', '/users', { id: USER_B, name: 'smoke-b', isActive: true });
    check('Admin 用指定 id 建用户', createdA?.data?.id === USER_A && createdB?.data?.id === USER_B,
        `A=${createdA?.data?.id} B=${createdB?.data?.id}`);

    // 2. JWT 能登录 gateway
    const jwtA = signTurmsJwt(secret, USER_A);
    const jwtB = signTurmsJwt(secret, USER_B);

    const clientB = new TurmsClient({ wsUrl: WS_URL });
    const inbox = [];
    clientB.messageService.addMessageListener((message) => inbox.push(message));
    await withTimeout(clientB.userService.login({ userId: String(USER_B), password: jwtB, deviceType: 'DESKTOP' }),
        'B 用 JWT 登录');
    check('JWT 能登录 turms-gateway', true, `user ${USER_B}`);

    // 3. Admin 代发，客户端真的收到
    await admin('POST', '/messages', {
        senderId: USER_A,
        senderDeviceType: 'DESKTOP',
        isGroupMessage: false,
        isSystemMessage: false,
        targetId: USER_B,
        text: 'smoke: hello from admin api',
    });
    try {
        await withTimeout(
            (async () => {
                while (inbox.length === 0) {
                    await new Promise((resolve) => setTimeout(resolve, 100));
                }
            })(),
            'B 收到代发的消息',
        );
        check('Admin 带 senderId 代发并投递到客户端', inbox[0]?.text === 'smoke: hello from admin api',
            `收到 ${inbox.length} 条`);
    } catch (error) {
        check('Admin 带 senderId 代发并投递到客户端', false, error.message);
    }

    // 4. 只有 QUERY 权限的客户端发不出消息
    const clientA = new TurmsClient({ wsUrl: WS_URL });
    await withTimeout(clientA.userService.login({ userId: String(USER_A), password: jwtA, deviceType: 'DESKTOP' }),
        'A 用 JWT 登录');
    let rejected = false;
    let rejectDetail = '';
    try {
        await withTimeout(clientA.messageService.sendMessage({
            isGroupMessage: false,
            targetId: String(USER_B),
            text: 'smoke: this must be rejected',
        }), 'A 尝试直连 Turms 发消息');
        rejectDetail = '未被拒绝（说明 statements 没生效）';
    } catch (error) {
        rejected = error?.code === 1106;
        rejectDetail = `code=${error?.code} reason=${error?.reason ?? error?.message}`;
    }
    check('QUERY-only 凭据发不出消息（UNAUTHORIZED_REQUEST 1106）', rejected, rejectDetail);

    await Promise.allSettled([clientA.driver.close(), clientB.driver.close()]);

    const failed = results.filter((item) => !item.ok);
    console.log(`\n${results.length - failed.length}/${results.length} 通过`);
    process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((error) => {
    console.error(`冒烟失败：${error.stack ?? error.message}`);
    process.exit(1);
});
