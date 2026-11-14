"""MoonChat 临时 Mock Biz 后端。

仅用于本地预览 Flutter Web。数据全在内存，进程退出后重置；不实现 Turms WebSocket。
启动：python frontend/mock_backend/mock_backend.py（默认 8081，8080 留给真 Biz）
前端：flutter run -d chrome --dart-define=MOONCHAT_API_BASE=http://localhost:8081
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import threading
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = "127.0.0.1"
PORT = int(os.environ.get("MOONCHAT_MOCK_PORT", "8081"))
NOW = timezone.utc


def iso_now() -> str:
    return datetime.now(NOW).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def iso_after(**kwargs: int) -> str:
    return (datetime.now(NOW) + timedelta(**kwargs)).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def account(account_id: int, name: str, kind: str = "human", email: str | None = None, owner: int | None = None) -> dict:
    return {
        "account_id": account_id,
        "display_name": name,
        "type": kind,
        "email": email,
        "owner_account_id": owner,
        "key": None,
    }


# Seed data makes first launch useful without setup.
accounts: dict[int, dict] = {
    1001: account(1001, "林岸", email="test@example.com"),
    1002: account(1002, "Luna", "agent", owner=1001),
    1003: account(1003, "阿澈"),
    1004: account(1004, "小满"),
    1005: account(1005, "Neo"),
    1006: account(1006, "月面气象台", "agent", owner=1001),
}
accounts[1002]["key"] = "mock-agent-key-1002"
accounts[1006]["key"] = "mock-agent-key-1006"

# pair -> {status, requested_by, created_at}
friendships: dict[tuple[int, int], dict] = {
    (1001, 1002): {"status": "accepted", "requested_by": 1001, "created_at": iso_now()},
    (1001, 1003): {"status": "accepted", "requested_by": 1001, "created_at": iso_now()},
    (1001, 1005): {"status": "pending", "requested_by": 1005, "created_at": iso_now()},
}

rooms: dict[int, dict] = {
    21: {"room_id": 21, "name": "月面基地", "owner_account_id": 1003, "created_at": iso_now(), "turms_group_id": "mock-group-21", "members": {1001, 1002, 1003, 1004}},
    22: {"room_id": 22, "name": "阿波罗计划", "owner_account_id": 1001, "created_at": iso_now(), "turms_group_id": "mock-group-22", "members": {1001, 1002, 1006}},
}

message_id = 10000
next_account_id = 1100
next_room_id = 30
# token -> account id. Mock tokens are opaque and never leave local preview.
tokens: dict[str, int] = {}
lock = threading.RLock()


def json_body(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", "0"))
    raw = handler.rfile.read(length) if length else b"{}"
    try:
        value = json.loads(raw.decode("utf-8"))
        return value if isinstance(value, dict) else {}
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}


def send_json(handler: BaseHTTPRequestHandler, status: int, value: object = None) -> None:
    payload = b"" if status == 204 or value is None else json.dumps(value, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Device-Type")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    if payload:
        handler.wfile.write(payload)


def error(handler: BaseHTTPRequestHandler, status: int, code: str, message: str, field: str | None = None) -> None:
    body = {"code": code, "message": message}
    if field:
        body["field"] = field
    send_json(handler, status, body)


def bearer(handler: BaseHTTPRequestHandler) -> int | None:
    value = handler.headers.get("Authorization", "")
    if not value.startswith("Bearer "):
        return None
    return tokens.get(value[7:].strip())


def require_auth(handler: BaseHTTPRequestHandler) -> int | None:
    account_id = bearer(handler)
    if account_id is None:
        error(handler, 401, "unauthenticated", "需要登录")
    return account_id


def pair(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def is_friend(a: int, b: int) -> bool:
    return friendships.get(pair(a, b), {}).get("status") == "accepted"


def public_account(a: dict) -> dict:
    return {"account_id": a["account_id"], "type": a["type"], "display_name": a["display_name"]}


def login_token(account_id: int) -> tuple[str, str]:
    token = "mock-owner-" + secrets.token_urlsafe(18)
    tokens[token] = account_id
    return token, iso_after(days=7)


def turms_session(account_id: int, owner_token: bool = True) -> dict:
    a = accounts[account_id]
    token, expires = login_token(account_id)
    result = {
        "account_id": account_id,
        "display_name": a["display_name"],
        "type": a["type"],
        "turms": {
            "user_id": account_id,
            "credential": "mock-turms-" + secrets.token_urlsafe(18),
            # No Turms server is started by this mock. Flutter will keep REST UI usable.
            "gateway_url": "ws://127.0.0.1:1",
        },
        "expires_at": iso_after(hours=12),
    }
    if owner_token:
        result["login_token"] = token
        result["login_expires_at"] = expires
    return result


def validate_name(value: object) -> str | None:
    value = str(value or "").strip()
    return value if value and len(value) <= 20 else None


class MockHandler(BaseHTTPRequestHandler):
    server_version = "MoonChatMock/1.0"

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[{self.command}] {self.path} - {fmt % args}")

    def do_OPTIONS(self) -> None:
        send_json(self, 204)

    def do_GET(self) -> None:
        self.route("GET")

    def do_POST(self) -> None:
        self.route("POST")

    def do_PATCH(self) -> None:
        self.route("PATCH")

    def do_DELETE(self) -> None:
        self.route("DELETE")

    def route(self, method: str) -> None:
        path = urlparse(self.path).path
        parts = [p for p in path.split("/") if p]
        body = json_body(self) if method in {"POST", "PATCH"} else {}
        try:
            with lock:
                self.dispatch(method, parts, parse_qs(urlparse(self.path).query), body)
        except Exception as exc:  # Keep mock alive while showing useful failure.
            print("mock error:", repr(exc))
            error(self, 500, "internal_error", "mock backend error")

    def dispatch(self, method: str, parts: list[str], query: dict[str, list[str]], body: dict) -> None:
        if parts[:2] == ["api", "auth"] and len(parts) == 3:
            if method == "POST" and parts[2] == "register":
                return self.register(body)
            if method == "POST" and parts[2] == "login":
                return self.login(body)
            if method == "POST" and parts[2] == "refresh":
                return self.refresh()

        if parts == ["api", "sessions"] and method == "POST":
            return self.sessions(body)

        me = require_auth(self)
        if me is None:
            return

        if parts == ["api", "accounts", "mine"] and method == "GET":
            mine = [a for a in accounts.values() if a["account_id"] == me or a["owner_account_id"] == me]
            return send_json(self, 200, {"items": [public_account(a) for a in sorted(mine, key=lambda x: x["account_id"])]})
        if parts == ["api", "agent-accounts"] and method == "POST":
            return self.create_agent(me, body)
        if parts == ["api", "accounts", "me"] and method == "PATCH":
            return self.rename(me, body)
        if len(parts) == 3 and parts[:2] == ["api", "accounts"] and method == "GET":
            return self.profile(me, int(parts[2])) if parts[2].isdigit() else error(self, 404, "not_found", "账号不存在")

        if parts == ["api", "friendships"]:
            if method == "GET":
                return self.friend_list(me, query)
            if method == "POST":
                return self.request_friend(me, body)
        if len(parts) == 3 and parts[:2] == ["api", "friendships"] and parts[2].isdigit() and method == "POST":
            return self.respond_friend(me, int(parts[2]), body)
        if len(parts) == 3 and parts[:2] == ["api", "friendships"] and parts[2].isdigit() and method == "DELETE":
            return self.delete_friend(me, int(parts[2]))

        if parts == ["api", "rooms"]:
            if method == "GET":
                return self.room_list(me)
            if method == "POST":
                return self.create_room(me, body)
        if len(parts) >= 3 and parts[:2] == ["api", "rooms"] and parts[2].isdigit():
            room_id = int(parts[2])
            if len(parts) == 3 and method == "GET":
                return self.room_detail(me, room_id)
            if len(parts) == 4 and parts[3] == "members":
                if method == "GET":
                    return self.member_list(me, room_id, query)
                if method == "POST":
                    return self.add_member(me, room_id, body)
            if len(parts) == 5 and parts[3] == "members" and method == "DELETE":
                if parts[4] == "me":
                    return self.leave_room(me, room_id)
                if parts[4].isdigit():
                    return self.remove_member(me, room_id, int(parts[4]))

        if len(parts) == 5 and parts[:2] == ["api", "conversations"] and parts[4] == "messages" and method == "POST":
            if parts[3].isdigit():
                return self.send_message(me, parts[2], int(parts[3]), body)

        error(self, 404, "not_found", "接口不存在")

    def register(self, body: dict) -> None:
        email = str(body.get("email", "")).strip().lower()
        password = str(body.get("password", ""))
        name = validate_name(body.get("display_name"))
        if "@" not in email or not name or len(password) < 8 or len(password) > 72 or password.isdigit():
            return error(self, 400, "validation_failed", "注册信息不合法")
        if any(a.get("email") == email for a in accounts.values()):
            return error(self, 409, "conflict", "邮箱已注册")
        global next_account_id
        account_id = next_account_id
        next_account_id += 1
        accounts[account_id] = account(account_id, name, email=email)
        return send_json(self, 201, {"account_id": account_id, "display_name": name, "type": "human"})

    def login(self, body: dict) -> None:
        email = str(body.get("email", "")).strip().lower()
        password = str(body.get("password", ""))
        if "@" not in email or not password:
            return error(self, 401, "unauthenticated", "邮箱或密码不对")
        found = next((a for a in accounts.values() if a.get("email") == email), None)
        # Temporary convenience: any unknown email gets a preview account.
        if found is None:
            global next_account_id
            found = account(next_account_id, email.split("@")[0][:20] or "预览账号", email=email)
            accounts[next_account_id] = found
            next_account_id += 1
        token, expires = login_token(found["account_id"])
        return send_json(self, 200, {"token": token, "expires_at": expires, "account": public_account(found)})

    def refresh(self) -> None:
        me = bearer(self)
        if me is None:
            return error(self, 401, "unauthenticated", "登录已失效")
        token, expires = login_token(me)
        return send_json(self, 200, {"token": token, "expires_at": expires, "account": public_account(accounts[me])})

    def sessions(self, body: dict) -> None:
        current = bearer(self)
        if "account_key" in body and current is None:
            key = str(body.get("account_key", ""))
            found = next((a for a in accounts.values() if a.get("key") == key), None)
            if found is None:
                return error(self, 401, "unauthenticated", "账号密钥无效")
            return send_json(self, 200, turms_session(found["account_id"], owner_token=False))
        if current is not None and "account_id" in body and str(body["account_id"]).isdigit():
            account_id = int(body["account_id"])
            target = accounts.get(account_id)
            if target is None:
                return error(self, 404, "not_found", "账号不存在")
            if account_id != current and target.get("owner_account_id") != current:
                return error(self, 403, "forbidden", "账号不属于当前归属者")
            return send_json(self, 200, turms_session(account_id))
        return error(self, 400, "validation_failed", "会话请求不合法")

    def create_agent(self, me: int, body: dict) -> None:
        if accounts[me]["type"] != "human":
            return error(self, 403, "forbidden", "agent 不能创建 agent")
        name = validate_name(body.get("display_name"))
        if not name:
            return error(self, 400, "validation_failed", "名字不合法")
        global next_account_id
        account_id = next_account_id
        next_account_id += 1
        key = str(uuid.uuid4())
        accounts[account_id] = account(account_id, name, "agent", owner=me)
        accounts[account_id]["key"] = key
        return send_json(self, 201, {"account_id": account_id, "display_name": name, "account_key": key})

    def rename(self, me: int, body: dict) -> None:
        name = validate_name(body.get("display_name"))
        if not name:
            return error(self, 400, "validation_failed", "名字不合法")
        accounts[me]["display_name"] = name
        return send_json(self, 200, {"account_id": me, "display_name": name, "updated_at": iso_now()})

    def profile(self, me: int, account_id: int) -> None:
        target = accounts.get(account_id)
        if target is None:
            return error(self, 404, "not_found", "账号不存在")
        return send_json(self, 200, {"account_id": account_id, "display_name": target["display_name"], "is_friend": is_friend(me, account_id)})

    def friend_list(self, me: int, query: dict) -> None:
        status = query.get("status", ["accepted"])[0]
        if status not in {"accepted", "pending"}:
            return error(self, 400, "validation_failed", "status 不合法")
        items = []
        for (a, b), relation in friendships.items():
            if me not in (a, b) or relation["status"] != status:
                continue
            peer = b if me == a else a
            incoming = status == "pending" and relation["requested_by"] != me
            # pending endpoint is defined as incoming requests only.
            if status == "pending" and not incoming:
                continue
            items.append({"peer_account_id": peer, "display_name": accounts[peer]["display_name"], "status": status, "incoming": incoming, "requested_at": relation["created_at"]})
        return send_json(self, 200, {"items": items})

    def request_friend(self, me: int, body: dict) -> None:
        raw = body.get("peer_account_id")
        if not isinstance(raw, int) or raw == me:
            return error(self, 400, "validation_failed", "账号 ID 不合法")
        if raw not in accounts:
            return error(self, 404, "not_found", "账号不存在")
        key = pair(me, raw)
        if key in friendships and friendships[key]["status"] in {"accepted", "pending"}:
            return error(self, 409, "conflict", "关系已存在")
        friendships[key] = {"status": "pending", "requested_by": me, "created_at": iso_now()}
        return send_json(self, 201, {"peer_account_id": raw, "status": "pending", "incoming": False})

    def respond_friend(self, me: int, peer: int, body: dict) -> None:
        relation = friendships.get(pair(me, peer))
        action = body.get("action")
        if action not in {"accept", "reject"}:
            return error(self, 400, "validation_failed", "action 不合法")
        if not relation or relation["status"] != "pending":
            return error(self, 404, "not_found", "待处理申请不存在")
        if relation["requested_by"] == me:
            return error(self, 403, "forbidden", "不能应答自己发出的申请")
        if action == "reject":
            del friendships[pair(me, peer)]
            return send_json(self, 204)
        relation["status"] = "accepted"
        return send_json(self, 200, {"peer_account_id": peer, "status": "accepted"})

    def delete_friend(self, me: int, peer: int) -> None:
        if not is_friend(me, peer):
            return error(self, 404, "not_found", "好友关系不存在")
        del friendships[pair(me, peer)]
        return send_json(self, 204)

    def room_list(self, me: int) -> None:
        items = []
        for room in rooms.values():
            if me in room["members"]:
                items.append({"room_id": room["room_id"], "name": room["name"], "owner_account_id": room["owner_account_id"], "joined_at": room["created_at"], "turms_group_id": room["turms_group_id"]})
        return send_json(self, 200, {"items": items})

    def create_room(self, me: int, body: dict) -> None:
        name = validate_name(body.get("name"))
        if not name:
            return error(self, 400, "validation_failed", "群名不合法")
        global next_room_id
        room_id = next_room_id
        next_room_id += 1
        room = {"room_id": room_id, "name": name, "owner_account_id": me, "created_at": iso_now(), "turms_group_id": f"mock-group-{room_id}", "members": {me}}
        rooms[room_id] = room
        return send_json(self, 201, {k: room[k] for k in ("room_id", "name", "owner_account_id", "created_at")})

    def room_detail(self, me: int, room_id: int) -> None:
        room = rooms.get(room_id)
        if not room:
            return error(self, 404, "not_found", "群不存在")
        if me not in room["members"]:
            return error(self, 403, "not_room_member", "你不在这个群里")
        return send_json(self, 200, {"room_id": room_id, "name": room["name"], "owner_account_id": room["owner_account_id"], "member_count": len(room["members"]), "created_at": room["created_at"]})

    def member_list(self, me: int, room_id: int, query: dict) -> None:
        room = rooms.get(room_id)
        if not room:
            return error(self, 404, "not_found", "群不存在")
        if me not in room["members"]:
            return error(self, 403, "not_room_member", "你不在这个群里")
        try:
            page, size = int(query.get("page", ["1"])[0]), int(query.get("size", ["50"])[0])
        except ValueError:
            return error(self, 400, "validation_failed", "分页参数不合法")
        if page < 1 or not 1 <= size <= 100:
            return error(self, 400, "validation_failed", "分页参数不合法")
        all_members = sorted(room["members"])
        start = (page - 1) * size
        items = [{"account_id": i, "display_name": accounts[i]["display_name"], "is_friend": i == me or is_friend(me, i), "joined_at": room["created_at"]} for i in all_members[start:start + size]]
        return send_json(self, 200, {"items": items, "page": page, "size": size, "total": len(all_members)})

    def add_member(self, me: int, room_id: int, body: dict) -> None:
        room = rooms.get(room_id)
        target = body.get("account_id")
        if not room:
            return error(self, 404, "not_found", "群不存在")
        if me not in room["members"]:
            return error(self, 403, "forbidden", "你不在这个群里")
        if not isinstance(target, int) or target not in accounts:
            return error(self, 404, "not_found", "账号不存在")
        if target in room["members"]:
            return error(self, 409, "conflict", "账号已在群里")
        room["members"].add(target)
        return send_json(self, 201, {"room_id": room_id, "account_id": target, "joined_at": iso_now()})

    def leave_room(self, me: int, room_id: int) -> None:
        room = rooms.get(room_id)
        if not room:
            return error(self, 404, "not_found", "群不存在")
        if room["owner_account_id"] == me:
            return error(self, 409, "owner_cannot_leave", "群主不能退群")
        if me not in room["members"]:
            return error(self, 403, "not_room_member", "你不在这个群里")
        room["members"].remove(me)
        return send_json(self, 204)

    def remove_member(self, me: int, room_id: int, target: int) -> None:
        room = rooms.get(room_id)
        if not room:
            return error(self, 404, "not_found", "群不存在")
        if me != room["owner_account_id"]:
            return error(self, 403, "forbidden", "只有群主能移除成员")
        if target == me:
            return error(self, 409, "owner_cannot_leave", "群主不能移除自己")
        if target not in room["members"]:
            return error(self, 404, "not_found", "成员不存在")
        room["members"].remove(target)
        return send_json(self, 204)

    def send_message(self, me: int, kind: str, target: int, body: dict) -> None:
        text = str(body.get("text", "")).strip()
        if kind not in {"dm", "room"} or not text or len(text) > 500:
            return error(self, 400, "validation_failed", "消息不合法")
        if kind == "dm":
            if target not in accounts:
                return error(self, 404, "not_found", "账号不存在")
            if target == me:
                return error(self, 400, "validation_failed", "不能给自己发消息")
            if not is_friend(me, target):
                return error(self, 403, "not_friend", "只有好友之间才能私聊")
        else:
            room = rooms.get(target)
            if not room:
                return error(self, 404, "not_found", "群不存在")
            if me not in room["members"]:
                return error(self, 403, "not_room_member", "你不在这个群里")
        global message_id
        message_id += 1
        sent_at = iso_now()
        return send_json(self, 201, {"message_id": message_id, "conversation": {"type": kind, "id": target}, "sent_at": sent_at})


if __name__ == "__main__":
    print(f"MoonChat mock backend: http://{HOST}:{PORT}")
    print("Preview account: test@example.com / any non-empty password")
    print("Data is in memory; no Turms WebSocket is provided.")
    ThreadingHTTPServer((HOST, PORT), MockHandler).serve_forever()
