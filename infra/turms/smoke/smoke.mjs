// Turms 端到端冒烟：一次性验证脚本。
//
// 验证 docs/truth/backend/messaging.md 描述的 Turms 运行时结论：
//   1. Admin API 能用指定 id 建用户（AddUserDTO.id）
//   2. Biz 用共享 HMAC 密钥签的 JWT 能登录 turms-gateway（gateway 的 type = jwt）
//   3. 只授 QUERY 的 JWT 发不出消息（CREATE_MESSAGE_REQUEST → UNAUTHORIZED_REQUEST，1106）
//   4. Admin API 能带 senderId 代发，消息真的投到目标账号的客户端会话
//   5. Admin API 能建 group，并由 Turms 生成 group id
//   6. Turms group 成员集合与 Admin API 的成员投影一致
//   7. 被移出群的账号再由 Admin API 代发群消息会被拒
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
// 密钥文件与 Turms 挂载的是同一份：infra/turms/secrets/jwt-hmac256.key
const SECRET_FILE = process.env.MOONCHAT_JWT_SECRET_FILE
    ?? path.join(import.meta.dirname, '..', 'secrets', 'jwt-hmac256.key');
// 每次跑用一对全新的账号：复用上次的 userId 会撞上上一个会话在 Redis 里残留的在线记录，
// 结果就是消息落库了但推送打到一个已经死掉的会话上（实测复现过）。
const RUN = Math.floor(Math.random() * 100_000);
const USER_A = 900_000 + RUN * 2;
const USER_B = USER_A + 1;
// service 默认缓存用户会话状态 60 秒；本地 standalone 首查可能缓存了 OFFLINE。
const TIMEOUT_MS = 90_000;

const results = [];

function check(name, ok, detail = '') {
    results.push({ name, ok });
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

function adminHeaders() {
    const basic = Buffer.from(`${ADMIN_USER}:${ADMIN_PASSWORD}`).toString('base64');
    return { Authorization: `Basic ${basic}`, 'Content-Type': 'application/json' };
}

async function admin(method, urlPath, body, raw = false) {
    const response = await fetch(`${ADMIN_URL}${urlPath}`, {
        method,
        headers: adminHeaders(),
        body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    const text = await response.text();
    if (!response.ok) {
        throw new Error(`${method} ${urlPath} → ${response.status} ${text}`);
    }
    if (!text) {
        return {};
    }
    return raw ? text : JSON.parse(text);
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
        const session = body?.data?.[0];
        if (session && session.status !== 'OFFLINE' && session.sessions?.length > 0) {
            return;
        }
        await new Promise((resolve) => setTimeout(resolve, 500));
    }
    throw new Error(`超时：${userId} 的会话一直没在 turms-service 侧变为在线`);
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

    // 3. Admin 私聊代发：落库并推送到目标客户端。
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
    check('代发的私聊消息推送到目标客户端', inbox.some((message) => message.text === text),
        `收到 ${inbox.length} 条`);

    // 4. Admin 建群。默认 GroupType 0 就是邀请制、成员可见、guest 不可发言。
    // group id 超出 Number.MAX_SAFE_INTEGER，必须从原始响应中取字符串，不能先 JSON.parse。
    const createdGroupText = await admin('POST', '/groups', {
        typeId: 0,
        creatorId: USER_A,
        ownerId: USER_A,
        name: `smoke group ${RUN}`,
    }, true);
    const groupId = /"id":(\d+)/.exec(createdGroupText)?.[1];
    check('Admin 建 group 成功并返回 group id', Boolean(groupId), `groupId=${groupId}`);
    if (!groupId) {
        throw new Error(`建 group 响应里没有 id：${createdGroupText}`);
    }

    // 5. 成员集合对齐：建群会自动加入 creator，再加入 B 后应正好是 A、B。
    await admin('POST', '/groups/members',
        `{"groupId":${groupId},"userId":${USER_B},"role":"MEMBER"}`);
    const membersAfterAdd = await admin('GET', `/groups/members?groupIds=${groupId}&size=100`);
    const memberIdsAfterAdd = membersAfterAdd.data.map((member) => member.key.userId).sort((a, b) => a - b);
    check('Turms 成员集合与投影一致', memberIdsAfterAdd.join(',') === `${USER_A},${USER_B}`,
        `members=${memberIdsAfterAdd.join(',')}`);

    // 6. 群消息同样走 Admin 代发，并应到达在线成员。
    const groupText = 'smoke: hello group from admin api';
    await admin('POST', '/messages',
        `{"senderId":${USER_A},"senderDeviceType":"DESKTOP","isGroupMessage":true,` +
        `"isSystemMessage":false,"targetId":${groupId},"text":"${groupText}"}`);
    const groupDeadline = Date.now() + 8_000;
    while (Date.now() < groupDeadline && !inbox.some((message) => message.text === groupText)) {
        await new Promise((resolve) => setTimeout(resolve, 100));
    }
    check('代发的群消息推送到在线成员', inbox.some((message) => message.text === groupText),
        `收到 ${inbox.length} 条`);

    // 7. 移出 B 后，Admin 带 B 的 senderId 代发群消息必须被 Turms 自己的成员校验拒绝。
    await admin('DELETE',
        `/groups/members?keys[0].groupId=${groupId}&keys[0].userId=${USER_B}`);
    const membersAfterDelete = await admin('GET', `/groups/members?groupIds=${groupId}&size=100`);
    const memberIdsAfterDelete = membersAfterDelete.data.map((member) => member.key.userId);
    check('移除成员后 Turms 成员集合同步更新', memberIdsAfterDelete.join(',') === `${USER_A}`,
        `members=${memberIdsAfterDelete.join(',')}`);
    let removedSenderRejected = false;
    let removeDetail = '';
    try {
        await admin('POST', '/messages',
            `{"senderId":${USER_B},"senderDeviceType":"DESKTOP","isGroupMessage":true,` +
            `"isSystemMessage":false,"targetId":${groupId},"text":"smoke: removed member"}`);
        removeDetail = '未被拒绝';
    } catch (error) {
        const status = Number(/→ (\d{3})/.exec(error.message)?.[1]);
        const code = Number(/"code":(\d+)/.exec(error.message)?.[1]);
        removedSenderRejected = status === 403 && code === 5009;
        removeDetail = `status=${status} code=${code}`;
    }
    check('被移出群的账号代发群消息被拒', removedSenderRejected, removeDetail);

    // 8. 只有 QUERY 权限的客户端发不出消息
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

    try {
        await admin('DELETE', `/groups?ids=${groupId}&deleteLogically=false`);
    } catch {
        // 冒烟结论已经产出，清理失败不覆盖结果。
    }
    await Promise.allSettled([clientA.driver.close(), clientB.driver.close()]);

    const failed = results.filter((item) => !item.ok);
    console.log(`\n${results.length - failed.length}/${results.length} 通过`);
    process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((error) => {
    console.error(`冒烟失败：${error.stack ?? error.message}`);
    process.exit(1);
});
