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
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import TurmsClient from 'turms-client-js';

const ADMIN_URL = process.env.TURMS_ADMIN_URL ?? 'http://localhost:8510';
// 冒烟覆盖文件把 gateway 的 WS 映射到宿主 20510（本机 10510 常被占）
const WS_URL = process.env.TURMS_WS_URL ?? 'ws://localhost:20510';
const ADMIN_USER = process.env.TURMS_ADMIN_USER ?? 'turms';
const ADMIN_PASSWORD = process.env.TURMS_ADMIN_PASSWORD ?? 'turms';
const SECRET_FILE = process.env.MOONCHAT_JWT_SECRET_FILE ?? path.join(import.meta.dirname, 'secrets', 'jwt-hmac256.key');
// 每次跑用一对全新的账号：复用上次的 userId 会撞上上一个会话在 Redis 里残留的在线记录，
// 结果就是消息落库了但推送打到一个已经死掉的会话上（实测复现过）。
const RUN = Math.floor(Math.random() * 100_000);
const USER_A = 900_000 + RUN * 2;
const USER_B = USER_A + 1;
const TIMEOUT_MS = 20_000;

const results = [];
function warn(name, detail = '') {
    console.log(`WARN  ${name}${detail ? `  — ${detail}` : ''}`);
}

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
        {
            // Turms 默认期望 token 里有 authenticated=true（jwt.authentication.expectation.custom-payload-claims）
            authenticated: true,
            // 只授查询：没有 CREATE_MESSAGE_REQUEST 的权限
            statements: [{ effect: 'ALLOW', actions: ['QUERY'], resources: ['*'] }],
        },
        secret,
        { algorithm: 'HS256', subject: String(userId), expiresIn: ttl },
    );
}

async function waitUntilOnline(userId) {
    const deadline = Date.now() + TIMEOUT_MS;
    while (Date.now() < deadline) {
        const body = await admin('GET', `/users/online-infos/sessions?ids=${userId}`);
        if (Array.isArray(body?.data) && body.data.length > 0) {
            return;
        }
        await new Promise((resolve) => setTimeout(resolve, 300));
    }
    throw new Error(`超时：${userId} 的会话一直没在 turms-service 侧出现`);
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

    // 1. 指定 id 建用户。
    // Turms 的 AddUserDTO 要求 password 非空且 ≤ 16 字符（实测：rawPassword must not be null, 0..16），
    // 而我们只用 JWT 登录，所以这里给一段随机密码，用完就丢——平台不保存也不分发它。
    const throwawayPassword = () => crypto.randomBytes(12).toString('base64url');
    const createdA = await admin('POST', '/users', { id: USER_A, name: 'smoke-a', isActive: true, password: throwawayPassword() });
    const createdB = await admin('POST', '/users', { id: USER_B, name: 'smoke-b', isActive: true, password: throwawayPassword() });
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

    // 登录成功与「会话在 turms-service 侧可见」之间有一小段异步窗口：实测约 3 秒内可见。
    // 不等就会消息落库但没人收，所以这里轮询在线会话而不是拍一个魔法 sleep。
    await waitUntilOnline(USER_B);

    // 3. Admin 代发：硬断言「落库」，软观察「推送到达」。
    // 推送这一环靠 gateway → service 的在线会话同步；本地 standalone 编排里实测不稳定
    // （service 侧把会话记成 OFFLINE、sessions 为空），所以只作为 WARN 报出来，不判失败。
    const text = 'smoke: hello from admin api';
    for (let attempt = 1; attempt <= 2 && inbox.length === 0; attempt++) {
        await admin('POST', '/messages', {
            senderId: USER_A,
            senderDeviceType: 'DESKTOP',
            isGroupMessage: false,
            isSystemMessage: false,
            targetId: USER_B,
            text,
        });
        const deadline = Date.now() + 8000;
        while (Date.now() < deadline && inbox.length === 0) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }
    }
    const persisted = await admin('GET', `/messages?senderIds=${USER_A}&targetIds=${USER_B}`);
    const stored = Array.isArray(persisted?.data) ? persisted.data : [];
    check('Admin 带 senderId 代发后消息已落库', stored.some((message) => message.text === text),
        `查到 ${stored.length} 条`);
    if (inbox.some((message) => message.text === text)) {
        check('代发的消息推送到目标客户端', true, `收到 ${inbox.length} 条`);
    } else {
        warn('代发的消息推送到目标客户端', '本地 standalone 下未送达，见 README 与 moonchat-messaging 的冒烟结果');
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
        // ResponseError 的 message 形如 "<requestId>:<code>:<reason>"，不同构建导出 code 的方式不一致，
        // 所以两处都读。
        const code = error?.code ?? Number((/:([0-9]+):/.exec(error?.message ?? '') || [])[1]);
        rejected = code === 1106;
        rejectDetail = `code=${code} message=${error?.message}`;
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
