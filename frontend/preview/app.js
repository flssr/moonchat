(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------------- theme ---------------- */
  const themeBtn = $("#themeBtn");
  const themeLabel = $(".themeBtn__label");

  function applyTheme(theme, persist) {
    document.documentElement.dataset.theme = theme;
    const dark = theme === "dark";
    if (themeBtn) {
      themeBtn.setAttribute("aria-pressed", String(dark));
      themeBtn.setAttribute("aria-label", dark ? "切换到白天模式" : "切换到夜间模式");
    }
    if (themeLabel) themeLabel.textContent = dark ? "白天" : "夜间";
    if (persist) {
      try { localStorage.setItem("moonchat-theme", theme); } catch (e) { /* file:// may deny */ }
    }
  }

  function initTheme() {
    const forced = new URLSearchParams(location.search).get("theme");
    if (forced === "dark" || forced === "light") {
      applyTheme(forced, false);
      return;
    }
    let saved = null;
    try { saved = localStorage.getItem("moonchat-theme"); } catch (e) { /* ignore */ }
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    applyTheme(saved || (prefersDark ? "dark" : "light"), false);
  }

  initTheme();
  if (themeBtn) {
    themeBtn.addEventListener("click", () => {
      const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
      applyTheme(next, true);
    });
  }

  /* ---------------- reveal + scroll spy ---------------- */
  if (!reduceMotion) {
    const revealTargets = $$(".section__head, .notes li, .compare figure, .foundation > .panel, .specGrid > .specCard, .duo > .panel, .handoff__col, .demoBar, .annot > div, .tableWrap, .closing, .demoNote");
    const revealIO = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-in");
        revealIO.unobserve(entry.target);
      });
    }, { threshold: 0.1, rootMargin: "0px 0px -6% 0px" });

    revealTargets.forEach((el, i) => {
      if (el.getBoundingClientRect().top < window.innerHeight * 0.98) return;
      el.classList.add("js-reveal");
      el.style.transitionDelay = `${(i % 4) * 45}ms`;
      revealIO.observe(el);
    });
  }

  const navLinks = $$(".rail__link");
  const sections = navLinks
    .map((link) => document.getElementById(link.getAttribute("href").slice(1)))
    .filter(Boolean);

  if (sections.length && "IntersectionObserver" in window) {
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        navLinks.forEach((link) => {
          link.classList.toggle("is-active", link.getAttribute("href") === `#${entry.target.id}`);
        });
      });
    }, { rootMargin: "-40% 0px -52% 0px", threshold: 0 });
    sections.forEach((section) => spy.observe(section));
  }

  /* ---------------- login demo ---------------- */
  const screen = $("#loginScreen");
  if (screen) {
    const form = $("#authForm");
    const nameField = $("#nameField");
    const nameInput = $("#loginName");
    const emailInput = $("#loginEmail");
    const passInput = $("#loginPass");
    const errEl = $("#loginErr");
    const eyeBtn = $("#eyeBtn");
    const enterBtn = $("#enterBtn");
    const caption = $("#stageCaption");
    const arrived = $("#arrived");
    const boardLabel = $("#boardLabel");
    const timers = [];
    let mode = "login";

    const later = (fn, ms) => { const t = setTimeout(fn, ms); timers.push(t); return t; };
    const clearTimers = () => { while (timers.length) clearTimeout(timers.pop()); };
    const rocketImgs = $$(".rocket__img");

    function setRocket(which) {
      rocketImgs.forEach((img, i) => img.classList.toggle("is-on", i === which));
    }

    function setPhase(phase) {
      screen.dataset.phase = phase;
      const captions = {
        idle: "01 / 舱门开启",
        closing: "02 / 舱门关闭中",
        armed: "03 / 点击登录",
        launching: "04 / 点火",
        arrived: "05 / 已抵达 · 月面基地 A-07"
      };
      caption.textContent = captions[phase] || "";
      const statusText = {
        closing: "正在验证，舱门关闭中…",
        armed: "验证通过。点击舱门上的登录按钮。",
        launching: "点火，正在离开月面。"
      };
      const status = $("#loginStatus");
      if (status) status.textContent = statusText[phase] || "";
      if (phase === "closing" || phase === "armed") setRocket(1);
      else if (phase === "launching") setRocket(2);
      else if (phase === "arrived") setRocket(-1);
      else setRocket(0);
      arrived.setAttribute("aria-hidden", String(phase !== "arrived"));
    }

    function reset() {
      clearTimers();
      setMode("login");
      setPhase("idle");
      form.reset();
      emailInput.type = "email";
      passInput.type = "password";
      eyeBtn.setAttribute("aria-pressed", "false");
      eyeBtn.setAttribute("aria-label", "显示密码");
      errEl.textContent = "";
      $$(".field", form).forEach((f) => f.classList.remove("is-error"));
      enterBtn.disabled = false;
      $("#boardBtn").disabled = false;
      $$("input", form).forEach((input) => { input.disabled = false; });
    }

    function setMode(next) {
      mode = next;
      $$(".modeToggle__btn").forEach((btn) => {
        const on = btn.dataset.mode === next;
        btn.classList.toggle("is-active", on);
        btn.setAttribute("aria-selected", String(on));
      });
      nameField.hidden = next === "login";
      boardLabel.textContent = next === "login" ? "登舱" : "注册并登舱";
      passInput.setAttribute("autocomplete", next === "login" ? "current-password" : "new-password");
      errEl.textContent = "";
      $$(".field", form).forEach((f) => f.classList.remove("is-error"));
    }

    function markError(field, message) {
      $$(".field", form).forEach((f) => f.classList.remove("is-error"));
      if (field) field.classList.add("is-error");
      errEl.textContent = message;
    }

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (screen.dataset.phase !== "idle") return;
      const email = emailInput.value.trim();
      const pass = passInput.value;
      const name = nameInput.value.trim();

      if (mode === "register" && (name.length === 0 || name.length > 20)) {
        markError(nameField, "名字要在 1–20 个字之间");
        nameInput.focus();
        return;
      }
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        markError(emailInput.closest(".field"), "邮箱格式不完整");
        emailInput.focus();
        return;
      }
      if (pass.length < 8 || pass.length > 72 || /^\d+$/.test(pass)) {
        markError(passInput.closest(".field"), "密码 8–72 位，且不能全是数字");
        passInput.focus();
        return;
      }

      errEl.textContent = "";
      $$(".field", form).forEach((f) => f.classList.remove("is-error"));
      $$("input", form).forEach((input) => { input.disabled = true; });
      $("#boardBtn").disabled = true;

      if (reduceMotion) {
        setPhase("armed");
        return;
      }
      setPhase("closing");
      later(() => {
        setPhase("armed");
        enterBtn.focus();
      }, 700);
    });

    $$(".modeToggle__btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        if (screen.dataset.phase !== "idle") return;
        setMode(btn.dataset.mode);
      });
    });

    [nameInput, emailInput, passInput].forEach((input) => {
      input.addEventListener("input", () => {
        input.closest(".field").classList.remove("is-error");
        errEl.textContent = "";
      });
    });

    eyeBtn.addEventListener("click", () => {
      const show = passInput.type === "password";
      passInput.type = show ? "text" : "password";
      eyeBtn.setAttribute("aria-pressed", String(show));
      eyeBtn.setAttribute("aria-label", show ? "隐藏密码" : "显示密码");
    });

    enterBtn.addEventListener("click", () => {
      if (screen.dataset.phase !== "armed") return;
      if (reduceMotion) {
        setPhase("arrived");
        return;
      }
      enterBtn.disabled = true;
      setPhase("launching");
      later(() => {
        setPhase("arrived");
      }, 1420);
    });

    $("#loginReset").addEventListener("click", reset);
    $("#againBtn").addEventListener("click", reset);
    $("#toChat").addEventListener("click", () => {
      $("#chat").scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    });
  }

  /* ---------------- client demo ---------------- */
  const app = $("#app");
  if (!app) return;

  const ME0 = 1001;
  const directory = {
    1001: { name: "林岸", mark: "林" },
    1002: { name: "Luna", mark: "L" },
    1003: { name: "阿澈", mark: "澈" },
    1004: { name: "小满", mark: "满" },
    1005: { name: "Neo", mark: "N" },
    1006: { name: "月面气象台", mark: "月" }
  };

  const seedAccounts = [
    { id: 1001, name: "林岸", type: "human" },
    { id: 1002, name: "Luna", type: "agent" }
  ];

  const seedRooms = [
    { id: 21, name: "月面基地", ownerId: 1003, members: [1001, 1002, 1003, 1004], mark: "月" },
    { id: 22, name: "阿波罗计划", ownerId: 1001, members: [1001, 1002, 1006], mark: "阿" }
  ];

  const seedConvs = [
    { key: "dm:1002", type: "dm", id: 1002, participants: [1001, 1002], time: "21:04", unread: 1 },
    { key: "room:21", type: "room", id: 21, time: "20:41", unread: 2 },
    { key: "dm:1003", type: "dm", id: 1003, participants: [1001, 1003], time: "19:12", unread: 0 },
    { key: "room:22", type: "room", id: 22, time: "昨天", unread: 0 }
  ];

  const seedThreads = {
    "dm:1002": [
      { from: 1002, text: "舱门已关闭，欢迎登舱。", time: "21:04" },
      { from: 1001, text: "外面星星很多。", time: "21:05" },
      { from: 1002, text: "这里是月面基地 A-07。想聊什么都可以，我在。", time: "21:05" }
    ],
    "room:21": [
      { divider: "今天" },
      { from: 1003, text: "今晚 23:40 有月食，露台的位子我占了三个。", time: "20:38" },
      { from: 1004, text: "带了两罐冰的月尘汽水。", time: "20:40" },
      { from: 1003, text: "今晚的月食别错过。", time: "20:41" }
    ],
    "dm:1003": [
      { divider: "今天" },
      { from: 1003, text: "第 3 次对接演练排到明早 09:00 了。", time: "19:10" },
      { from: 1001, text: "收到，我提前 20 分钟进舱。", time: "19:12" }
    ],
    "room:22": [
      { divider: "昨天" },
      { from: 1006, text: "明日无尘暴，能见度 21 km，适合出舱。", time: "06:00" },
      { from: 1001, text: "好，我明早去检查天线。", time: "07:15" }
    ]
  };

  const seedFriends = { 1001: [1002, 1003, 1004], 1002: [1001] };
  const seedIncoming = { 1001: [1005], 1002: [] };

  let accounts = JSON.parse(JSON.stringify(seedAccounts));
  let rooms = JSON.parse(JSON.stringify(seedRooms));
  let conversations = JSON.parse(JSON.stringify(seedConvs));
  let threads = JSON.parse(JSON.stringify(seedThreads));
  let friends = JSON.parse(JSON.stringify(seedFriends));
  let incoming = JSON.parse(JSON.stringify(seedIncoming));
  let outgoing = {};
  let activeAccountId = ME0;
  let activeConvKey = "dm:1002";
  let convFilter = "all";
  let friendsTab = "friends";
  let selectedContact = null;
  let profileId = null;
  let view = "messages";

  const refs = {
    convList: $("#convList"),
    msgList: $("#msgList"),
    roomName: $("#roomName"),
    roomStatus: $("#roomStatus"),
    roomAvatar: $("#roomAvatar"),
    msgInput: $("#msgInput"),
    sendBtn: $("#sendBtn"),
    info: $("#infoPanel"),
    contactsDetail: $("#contactsDetail"),
    contactList: $("#contactList"),
    accountList: $("#accountList"),
    accountDetail: $("#accountDetail"),
    profileSheet: $("#profileSheet"),
    profileBody: $("#profileBody"),
    scrim: $("#sheetScrim"),
    toast: null
  };

  const me = () => accounts.find((a) => a.id === activeAccountId) || accounts[0];
  const currentFriends = () => (friends[activeAccountId] || []).slice();
  const currentIncoming = () => (incoming[activeAccountId] || []).slice();

  const escapeHTML = (value) => String(value)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

  const nowTime = () => new Date().toTimeString().slice(0, 5);

  function toast(message) {
    if (!refs.toast) {
      refs.toast = document.createElement("div");
      refs.toast.className = "toast";
      refs.toast.setAttribute("role", "status");
      app.appendChild(refs.toast);
    }
    refs.toast.textContent = message;
    refs.toast.classList.add("is-on");
    clearTimeout(toast._t);
    toast._t = setTimeout(() => refs.toast.classList.remove("is-on"), 2400);
  }

  function roomOf(id) { return rooms.find((r) => r.id === id); }
  function convKey(type, id) { return `${type}:${id}`; }
  function accountName(id) { return directory[id]?.name || `账号 ${id}`; }
  function accountMark(id) { return directory[id]?.mark || "?"; }

  function convMeta(conv) {
    if (conv.type === "dm") {
      return { name: accountName(conv.id), mark: accountMark(conv.id), status: "好友 · 私聊" };
    }
    const room = roomOf(conv.id);
    return {
      name: room ? room.name : "群聊",
      mark: room ? room.mark : "群",
      status: room ? `${room.members.length} 位成员 · ${room.ownerId === activeAccountId ? "你是群主" : "成员"}` : "群聊"
    };
  }

  function visibleConversations() {
    return conversations.filter((conv) => {
      if (conv.type === "dm") {
        return conv.id !== activeAccountId
          && (!conv.participants || conv.participants.includes(activeAccountId));
      }
      const room = roomOf(conv.id);
      return room && room.members.includes(activeAccountId);
    });
  }

  function lastPreview(conv) {
    const list = (threads[conv.key] || []).filter((m) => !m.divider);
    const last = list[list.length - 1];
    if (!last) return "还没有消息";
    if (conv.type === "room" && last.from !== activeAccountId) {
      return `${accountName(last.from)}：${last.text}`;
    }
    return last.text;
  }

  function renderConvList() {
    const list = visibleConversations().filter((conv) => {
      if (convFilter === "dm") return conv.type === "dm";
      if (convFilter === "room") return conv.type === "room";
      return true;
    });

    refs.convList.innerHTML = "";
    $("#convCount").textContent = String(visibleConversations().length);

    if (!list.length) {
      const empty = document.createElement("p");
      empty.className = "formHint";
      empty.style.padding = "14px 12px";
      empty.textContent = "这个账号还没有会话。先加好友，或被拉进群。";
      refs.convList.appendChild(empty);
      return;
    }

    list.forEach((conv) => {
      const meta = convMeta(conv);
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `conv${conv.key === activeConvKey ? " is-active" : ""}`;
      btn.setAttribute("role", "listitem");
      btn.dataset.key = conv.key;
      btn.innerHTML = `
        <span class="avatar">${escapeHTML(meta.mark)}</span>
        <span class="conv__main">
          <span class="conv__name">${escapeHTML(meta.name)}</span>
          <span class="conv__preview">${escapeHTML(lastPreview(conv))}</span>
        </span>
        <span class="conv__meta">
          <span class="conv__time">${escapeHTML(conv.time)}</span>
          ${conv.unread ? `<span class="conv__unread">${conv.unread}</span>` : ""}
        </span>`;
      btn.addEventListener("click", () => selectConversation(conv.key));
      refs.convList.appendChild(btn);
    });
  }

  function selectConversation(key) {
    const conv = conversations.find((c) => c.key === key);
    if (!conv) return;
    activeConvKey = key;
    conv.unread = 0;
    view = "messages";
    app.dataset.view = "messages";
    app.classList.remove("show-convs");
    setViewButtons("messages");
    closeProfile();
    renderConvList();
    renderRoom();
    renderInfo();
  }

  function renderRoom() {
    const conv = conversations.find((c) => c.key === activeConvKey);
    if (!conv) {
      refs.roomName.textContent = "没有会话";
      refs.roomStatus.textContent = "先加好友，或被拉进群";
      refs.roomAvatar.textContent = "—";
      refs.msgList.innerHTML = `<div class="emptyState" style="margin:60px auto 0"><p class="micro">空</p><p>这个账号还没有会话。可以从联系人里选一位好友开始私聊，或者等一个群邀请。</p></div>`;
      refs.msgInput.disabled = true;
      refs.msgInput.placeholder = "先开始一段关系";
      refs.sendBtn.disabled = true;
      renderInfo();
      return;
    }

    const meta = convMeta(conv);
    refs.roomName.textContent = meta.name;
    refs.roomStatus.textContent = meta.status;
    refs.roomAvatar.textContent = meta.mark;
    refs.msgInput.disabled = false;
    refs.msgInput.placeholder = conv.type === "dm" ? `发一条消息给 ${meta.name}…` : `发一条消息到 ${meta.name}…`;

    const thread = threads[conv.key] || [];
    refs.msgList.innerHTML = "";
    let lastFrom = null;

    if (!thread.length) {
      refs.msgList.innerHTML = `<div class="emptyState" style="margin:60px auto 0"><p class="micro">还没有消息</p><p>${conv.readonly ? "你们已经不是好友，历史消息只读。" : "关系已经成立，发第一句话吧。"}</p></div>`;
    }

    thread.forEach((msg) => {
      if (msg.divider) {
        const day = document.createElement("div");
        day.className = "day";
        day.innerHTML = `<span>${escapeHTML(msg.divider)}</span>`;
        refs.msgList.appendChild(day);
        lastFrom = null;
        return;
      }

      const mine = msg.from === activeAccountId;
      const continuation = lastFrom === msg.from;
      const row = document.createElement("div");
      row.className = `msg ${mine ? "msg--me" : ""}${continuation ? " msg--continuation" : ""}`;
      const senderLabel = conv.type === "room" && msg.from !== activeAccountId
        ? `<span class="msg__sender">${escapeHTML(accountName(msg.from))}</span>` : "";
      const stateLabel = msg.state === "sending" ? "发送中…" : msg.state === "failed" ? "发送失败" : msg.time;
      row.innerHTML = `
        ${mine ? "" : `<span class="avatar msg__avatar" aria-hidden="true">${escapeHTML(accountMark(msg.from))}</span>`}
        <div class="msg__body">
          ${senderLabel}
          <span class="bubbleText">${escapeHTML(msg.text)}</span>
          <span class="msg__time">${escapeHTML(stateLabel)}</span>
        </div>`;
      refs.msgList.appendChild(row);
      lastFrom = msg.from;
    });

    if (conv.readonly) {
      const note = document.createElement("p");
      note.className = "demoNote";
      note.style.padding = "10px 2px";
      note.textContent = "已不是好友：历史消息保留只读，不能再发新消息。";
      refs.msgList.appendChild(note);
      refs.msgInput.disabled = true;
      refs.msgInput.placeholder = "已不是好友，无法发送";
      refs.sendBtn.disabled = true;
    }

    refs.msgList.scrollTop = refs.msgList.scrollHeight;
    renderInfo();
  }

  function renderInfo() {
    const conv = conversations.find((c) => c.key === activeConvKey);
    const panel = refs.info;
    if (!conv) { panel.innerHTML = ""; return; }

    if (conv.type === "dm") {
      const id = conv.id;
      const isFriend = currentFriends().includes(id);
      panel.innerHTML = `
        <div class="info__head"><span>会话信息</span><button class="iconBtn" type="button" data-close-info aria-label="收起会话信息"><svg aria-hidden="true"><use href="#i-close"/></svg></button></div>
        <div class="info__profile">
          <span class="avatar avatar--xl">${escapeHTML(accountMark(id))}</span>
          <b>${escapeHTML(accountName(id))}</b>
          <em class="info__id">账号 ${id}</em>
          <div class="chips">${isFriend ? "<span>好友</span>" : "<span>非好友</span>"}</div>
        </div>
        <div class="info__block">
          <h4>关系</h4>
          <p class="info__hint">${isFriend ? "私聊只在好友之间成立。删除好友后，历史消息保留只读，不能再发新消息。" : "非好友之间不能私聊。"}</p>
        </div>
        <div class="info__actions">
          <button class="btn" type="button" data-open-profile="${id}">查看资料</button>
          ${isFriend ? `<button class="btn btn--danger" type="button" data-remove-friend="${id}">删除好友</button>` : ""}
        </div>`;
    } else {
      const room = roomOf(conv.id);
      if (!room) { panel.innerHTML = ""; return; }
      const isOwner = room.ownerId === activeAccountId;
      panel.innerHTML = `
        <div class="info__head"><span>群信息</span><button class="iconBtn" type="button" data-close-info aria-label="收起会话信息"><svg aria-hidden="true"><use href="#i-close"/></svg></button></div>
        <div class="info__profile">
          <span class="avatar avatar--xl">${escapeHTML(room.mark)}</span>
          <b>${escapeHTML(room.name)}</b>
          <em class="info__id">群 ${room.id} · ${room.members.length} 人</em>
          <div class="chips"><span>${isOwner ? "你是群主" : "成员"}</span></div>
        </div>
        <div class="info__block">
          <h4>成员 <span>${room.members.length}</span></h4>
          <div class="memberList">
            ${room.members.map((id) => `
              <div class="memberRow">
                <button class="memberRow__open" type="button" data-open-profile="${id}">
                  <span class="avatar">${escapeHTML(accountMark(id))}</span>
                  <span class="memberRow__main">
                    <span class="memberRow__name">${escapeHTML(accountName(id))}${id === room.ownerId ? ' <span class="tag tag--owner">群主</span>' : ""}</span>
                    <span class="memberRow__id">账号 ${id}</span>
                  </span>
                </button>
                ${isOwner && id !== room.ownerId ? `<button class="iconBtn memberRow__remove" type="button" data-kick="${id}" aria-label="移除 ${escapeHTML(accountName(id))}"><svg aria-hidden="true"><use href="#i-close"/></svg></button>` : ""}
              </div>`).join("")}
          </div>
          <form class="inviteRow" data-invite-form>
            <input type="text" inputmode="numeric" placeholder="账号 ID" aria-label="邀请账号 ID">
            <button class="btn btn--small" type="submit">邀请</button>
          </form>
        </div>
        <div class="info__actions">
          <button class="btn" type="button" data-open-profile="${room.ownerId}">查看群主资料</button>
          ${isOwner
            ? `<button class="btn" type="button" disabled>群主不能退群</button><p class="info__hint">V1 没有群主转让，也没有解散群。</p>`
            : `<button class="btn btn--danger" type="button" data-leave-room="${room.id}">退出群聊</button>`}
        </div>`;
    }
  }

  function renderContacts() {
    $("#friendCount").textContent = String(currentFriends().length);
    $("#requestCount").textContent = String(currentIncoming().length);
    $("#reqDot").hidden = currentIncoming().length === 0;
    $("#accountCount").textContent = String(accounts.length);

    $$(".tab[data-friends-tab]").forEach((tab) => {
      const on = tab.dataset.friendsTab === friendsTab;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", String(on));
    });

    refs.contactList.innerHTML = "";

    if (friendsTab === "friends") {
      const list = currentFriends();
      if (!list.length) {
        refs.contactList.innerHTML = `<p class="formHint" style="padding:14px 10px">还没有好友。加好友需要对方的账号 ID 或主页链接。</p>`;
      }
      list.forEach((id) => {
        const row = document.createElement("button");
        row.type = "button";
        row.className = `contactRow${selectedContact === id ? " is-active" : ""}`;
        row.innerHTML = `
          <span class="avatar">${escapeHTML(accountMark(id))}</span>
          <span class="contactRow__main">
            <span class="contactRow__name">${escapeHTML(accountName(id))}</span>
            <span class="contactRow__id">账号 ${id}</span>
          </span>
          <svg class="convs__meChev" aria-hidden="true"><use href="#i-chev"/></svg>`;
        row.addEventListener("click", () => {
          selectedContact = id;
          renderContacts();
          renderContactDetail(id);
        });
        refs.contactList.appendChild(row);
      });
    } else {
      const list = currentIncoming();
      if (!list.length) {
        refs.contactList.innerHTML = `<p class="formHint" style="padding:14px 10px">没有待处理的申请。</p>`;
      }
      list.forEach((id) => {
        const row = document.createElement("div");
        row.className = "requestRow";
        row.innerHTML = `
          <div class="requestRow__top">
            <span class="avatar">${escapeHTML(accountMark(id))}</span>
            <span class="requestRow__meta"><b>${escapeHTML(accountName(id))}</b><em>账号 ${id} · 想加你为好友</em></span>
          </div>
          <div class="requestRow__actions">
            <button class="btn btn--primary btn--small" type="button" data-accept="${id}">同意</button>
            <button class="btn btn--small" type="button" data-reject="${id}">拒绝</button>
          </div>`;
        refs.contactList.appendChild(row);
      });
    }
  }

  function detailCard(id, options = {}) {
    const isFriend = currentFriends().includes(id);
    const isSelf = id === activeAccountId;
    const hasIncoming = currentIncoming().includes(id);
    const hasOutgoing = (outgoing[activeAccountId] || []).includes(id);
    const tag = isFriend ? '<span class="tag">好友</span>' : hasIncoming ? '<span class="tag tag--muted">待处理</span>' : "";

    let actions = "";
    if (isSelf) {
      actions = `<p class="detailCard__note">这是当前账号。账号资料页只展示名字、ID 和好友状态。</p>`;
    } else if (isFriend) {
      actions = `
        <div class="detailCard__actions">
          <button class="btn btn--primary" type="button" data-dm="${id}">发消息</button>
          ${options.compact ? "" : `<button class="btn btn--danger" type="button" data-remove-friend="${id}">删除好友</button>`}
        </div>
        <p class="detailCard__note">私聊入口只对好友出现。删除后历史保留只读。</p>`;
    } else if (hasIncoming) {
      actions = `
        <div class="detailCard__actions">
          <button class="btn btn--primary" type="button" data-accept="${id}">同意申请</button>
          <button class="btn" type="button" data-reject="${id}">拒绝</button>
        </div>
        <p class="detailCard__note">对方已经发来申请。同意后私聊入口才会出现。</p>`;
    } else if (hasOutgoing) {
      actions = `<div class="detailCard__actions"><button class="btn" type="button" disabled>已申请</button></div><p class="detailCard__note">申请发出后不能撤回，对方同意前不会有私聊入口。</p>`;
    } else {
      actions = `
        <div class="detailCard__actions">
          <button class="btn btn--primary" type="button" data-add-friend="${id}">加好友</button>
        </div>
        <p class="detailCard__note">不是好友时，资料页只有“加好友”，没有发消息。</p>`;
    }

    return `
      <div class="detailCard">
        <div class="detailCard__top">
          <span class="avatar avatar--xl">${escapeHTML(accountMark(id))}</span>
          <div>
            <div class="detailCard__name">${escapeHTML(accountName(id))}</div>
            <div class="detailCard__id">账号 ${id}</div>
            <div class="detailCard__desc" style="margin-top:6px">${tag}</div>
          </div>
        </div>
        ${options.error ? `<p class="detailCard__desc" style="color:var(--accent)">${escapeHTML(options.error)}</p>` : ""}
        ${actions}
      </div>`;
  }

  function renderContactDetail(id) {
    if (!id) return;
    refs.contactsDetail.innerHTML = detailCard(id);
  }

  function renderAccounts() {
    $("#accountCount").textContent = String(accounts.length);
    refs.accountList.innerHTML = accounts.map((account) => `
      <div class="accountRow${account.id === activeAccountId ? " is-current" : ""}">
        <span class="avatar">${escapeHTML(accountMark(account.id))}</span>
        <span class="accountRow__main">
          <span class="accountRow__name">${escapeHTML(account.name)}${account.type === "agent" ? ' <span class="tag tag--muted">agent</span>' : ""}</span>
          <span class="accountRow__meta">账号 ${account.id} · ${account.type === "human" ? "真人" : "归属者 1001"}</span>
        </span>
        ${account.id === activeAccountId
          ? '<span class="tag">当前</span>'
          : `<button class="btn btn--small" type="button" data-switch="${account.id}">切进</button>`}
      </div>`).join("");
  }

  function renderAll() {
    const current = me();
    $("#meAvatar").textContent = accountMark(current.id);
    $("#meName").textContent = current.name;
    $("#meId").textContent = `账号 ${current.id}`;

    const visible = visibleConversations();
    if (!visible.some((c) => c.key === activeConvKey)) {
      activeConvKey = visible[0]?.key || "";
    }
    renderConvList();
    renderRoom();
    renderContacts();
    renderAccounts();

    if (view === "contacts" && selectedContact) renderContactDetail(selectedContact);
    if (view === "account") renderAccountDetail();
  }

  function setView(next) {
    view = next;
    app.dataset.view = next;
    app.classList.remove("show-convs");
    setViewButtons(next);
    closeProfile();
    if (next === "messages") {
      renderRoom();
    } else if (next === "contacts") {
      renderContacts();
      if (selectedContact) renderContactDetail(selectedContact);
    } else {
      renderAccounts();
      renderAccountDetail();
    }
  }

  function setViewButtons(next) {
    $$(".appRail__btn[data-view]").forEach((btn) => {
      const on = btn.dataset.view === next;
      btn.classList.toggle("is-active", on);
      btn.setAttribute("aria-pressed", String(on));
    });
  }

  function openProfile(id) {
    profileId = id;
    refs.profileBody.innerHTML = detailCard(id, { compact: true });
    refs.profileSheet.hidden = false;
    refs.scrim.hidden = false;
    refs.profileSheet.style.animation = "none";
    void refs.profileSheet.offsetWidth;
    refs.profileSheet.style.animation = "";
    $("#profileClose").focus();
  }

  function closeProfile() {
    profileId = null;
    refs.profileSheet.hidden = true;
    refs.scrim.hidden = true;
  }

  function startDm(id) {
    const key = convKey("dm", id);
    let conv = conversations.find((c) => c.key === key);
    if (!conv) {
      conv = { key, type: "dm", id, participants: [activeAccountId, id], time: nowTime(), unread: 0 };
      conversations.unshift(conv);
      threads[key] = threads[key] || [];
    }
    closeProfile();
    setView("messages");
    selectConversation(key);
    refs.msgInput.focus();
  }

  function sendMessage() {
    const conv = conversations.find((c) => c.key === activeConvKey);
    const text = refs.msgInput.value.trim();
    if (!conv || !text || conv.readonly) return;

    const message = { from: activeAccountId, text, time: nowTime(), state: "sending" };
    threads[conv.key] = threads[conv.key] || [];
    threads[conv.key].push(message);
    conv.time = message.time;
    conv.preview = text;
    refs.msgInput.value = "";
    updateCounter();
    renderRoom();
    renderConvList();
    refs.msgList.scrollTop = refs.msgList.scrollHeight;

    const target = conv.key;
    setTimeout(() => {
      message.state = "sent";
      if (activeConvKey === target) renderRoom();
    }, 500);

    if (target === "dm:1002" && activeAccountId === 1001) {
      setTimeout(() => {
        threads[target].push({
          from: 1002,
          text: "收到，我在。舷窗外现在是月夜。",
          time: nowTime()
        });
        if (activeConvKey === target) {
          renderRoom();
          refs.msgList.scrollTop = refs.msgList.scrollHeight;
        }
        renderConvList();
      }, 1600);
    }
  }

  function updateCounter() {
    const len = refs.msgInput.value.length;
    $("#charCount").textContent = len >= 400 ? `${len} / 500` : "";
    refs.sendBtn.disabled = !len || len > 500;
  }

  function removeFriend(id) {
    friends[activeAccountId] = currentFriends().filter((f) => f !== id);
    const key = convKey("dm", id);
    const conv = conversations.find((c) => c.key === key);
    if (conv) conv.readonly = true;
    incoming[activeAccountId] = currentIncoming().filter((f) => f !== id);
    toast(`已删除 ${accountName(id)}，历史消息只读`);
    selectedContact = null;
    closeProfile();
    renderAll();
  }

  function acceptRequest(id) {
    incoming[activeAccountId] = currentIncoming().filter((f) => f !== id);
    if (!currentFriends().includes(id)) {
      friends[activeAccountId] = currentFriends().concat(id);
    }
    toast(`已同意 ${accountName(id)}，可以开始私聊了`);
    renderAll();
    if (view === "contacts") {
      if (friendsTab === "friends") renderContactDetail(id);
      else refs.contactsDetail.innerHTML = "";
    }
    if (profileId === id) refs.profileBody.innerHTML = detailCard(id, { compact: true });
  }

  function rejectRequest(id) {
    incoming[activeAccountId] = currentIncoming().filter((f) => f !== id);
    toast(`已忽略 ${accountName(id)} 的申请`);
    renderAll();
    closeProfile();
    refs.contactsDetail.innerHTML = "";
  }

  function sendFriendRequest(id) {
    outgoing[activeAccountId] = (outgoing[activeAccountId] || []).concat(id);
    toast(`已向 ${accountName(id)} 发出好友申请`);
    renderContacts();
    if (view === "contacts") renderContactDetail(id);
    if (profileId === id) refs.profileBody.innerHTML = detailCard(id, { compact: true });
  }

  function lookupAccount(raw) {
    const value = String(raw).trim();
    if (!/^\d+$/.test(value)) {
      return { error: "账号 ID 只能是数字。" };
    }
    const id = Number(value);
    if (!directory[id]) {
      return { error: "not_found：这个账号不存在。" };
    }
    return { id };
  }

  function renderAccountDetail(mode = "empty", payload = {}) {
    if (mode === "empty") {
      refs.accountDetail.innerHTML = `
        <div class="emptyState">
          <p class="micro">Agent 账号</p>
          <p>agent 和真人是同一种账号，没有第二套身份。创建后只会看到一次密钥，关掉就再也拿不到。</p>
          ${me().type === "human"
            ? `<button class="btn" type="button" data-create-agent>创建 agent 账号</button>`
            : `<p class="detailCard__note">当前是 agent 账号。agent 不能创建新的 agent。</p>`}
        </div>`;
      return;
    }

    if (mode === "form") {
      refs.accountDetail.innerHTML = `
        <form class="agentForm" id="agentForm">
          <h3>创建 agent 账号</h3>
          <p>给它一个名字，平台会同时创建一个 Turms 用户。密钥只在这个响应里出现一次。</p>
          <label class="field"><span class="field__label">名字</span><input id="agentName" type="text" maxlength="20" placeholder="最多 20 个字" autocomplete="off"></label>
          <p class="formHint" id="agentErr"></p>
          <div class="detailCard__actions">
            <button class="btn btn--primary" type="submit">创建并生成密钥</button>
            <button class="btn" type="button" data-cancel-agent>取消</button>
          </div>
        </form>`;
      $("#agentName").focus();
      return;
    }

    if (mode === "key") {
      refs.accountDetail.innerHTML = `
        <div class="keyResult">
          <p class="micro">已创建 · 账号 ${payload.id}</p>
          <h3>${escapeHTML(payload.name)}</h3>
          <p class="detailCard__desc">把这串密钥交给 agent 服务，用它调 <code>POST /api/sessions</code> 换 Turms 凭据。平台只存哈希，关掉这个页面就再也看不到明文。</p>
          <div class="keyBox">
            <code id="agentKey">${escapeHTML(payload.key)}</code>
            <button class="iconBtn" type="button" data-copy-key aria-label="复制密钥"><svg aria-hidden="true"><use href="#i-copy"/></svg></button>
          </div>
          <p class="warnText">只显示一次。不要贴进群聊、日志或截图。</p>
          <div class="detailCard__actions">
            <button class="btn btn--primary" type="button" data-finish-key>我保存好了</button>
          </div>
        </div>`;
    }
  }

  function switchAccount(id) {
    const account = accounts.find((a) => a.id === id);
    if (!account) return;
    activeAccountId = id;
    selectedContact = null;
    profileId = null;
    closeProfile();
    const visible = visibleConversations();
    activeConvKey = visible[0]?.key || "";
    setView("messages");
    renderAll();
    toast(`已切到 ${account.name} · 账号 ${account.id}`);
  }

  function createAgent(name) {
    const id = 1100 + accounts.filter((a) => a.type === "agent").length;
    accounts.push({ id, name, type: "agent" });
    directory[id] = { name, mark: name.slice(0, 1) };
    friends[id] = [1001];
    incoming[id] = [];
    outgoing[id] = [];
    const key = (crypto && crypto.randomUUID)
      ? crypto.randomUUID()
      : "6f1c2a4e-9d3b-4c77-8e21-7a0f5b2d9c10";
    renderAccounts();
    renderAccountDetail("key", { id, name, key });
    toast(`已创建 agent 账号 ${name}`);
  }

  function copyKey(key) {
    const done = () => toast("密钥已复制");
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(key).then(done).catch(() => toast("复制失败，请手动选中"));
    } else {
      toast("复制失败，请手动选中");
    }
  }

  /* ---------------- events ---------------- */
  $$(".appRail__btn[data-view]").forEach((btn) => {
    btn.addEventListener("click", () => setView(btn.dataset.view));
  });

  $("#meRow").addEventListener("click", () => setView("account"));
  $("#listBtn").addEventListener("click", () => {
    app.classList.toggle("show-convs");
    if (app.classList.contains("show-convs")) {
      const first = $(".conv", refs.convList);
      if (first) first.focus();
    }
  });
  $("#newChatBtn").addEventListener("click", () => {
    setView("contacts");
    toast("私聊只能从好友开始，或者去群里说话。");
  });

  $("#convList").addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.target.classList.contains("conv")) {
      event.target.click();
    }
  });

  $$(".tab[data-filter]").forEach((tab) => {
    tab.addEventListener("click", () => {
      convFilter = tab.dataset.filter;
      $$(".tab[data-filter]").forEach((t) => {
        const on = t === tab;
        t.classList.toggle("is-active", on);
        t.setAttribute("aria-selected", String(on));
      });
      renderConvList();
    });
  });

  $$(".tab[data-friends-tab]").forEach((tab) => {
    tab.addEventListener("click", () => {
      friendsTab = tab.dataset.friendsTab;
      selectedContact = null;
      refs.contactsDetail.innerHTML = "";
      renderContacts();
    });
  });

  refs.msgInput.addEventListener("input", updateCounter);
  refs.msgInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      sendMessage();
    }
  });
  refs.sendBtn.addEventListener("click", sendMessage);

  $("#infoBtn").addEventListener("click", () => {
    const off = app.classList.toggle("no-info");
    $("#infoBtn").setAttribute("aria-pressed", String(!off));
    $("#infoBtn").setAttribute("aria-label", off ? "展开会话信息" : "收起会话信息");
  });

  app.addEventListener("click", (event) => {
    const target = event.target.closest("[data-close-info],[data-open-profile],[data-add-friend],[data-accept],[data-reject],[data-dm],[data-remove-friend],[data-leave-room],[data-kick],[data-switch],[data-create-agent],[data-cancel-agent],[data-copy-key],[data-finish-key]");
    if (!target) return;

    if (target.hasAttribute("data-close-info")) {
      app.classList.add("no-info");
      $("#infoBtn").setAttribute("aria-pressed", "false");
      return;
    }
    if (target.hasAttribute("data-open-profile")) {
      openProfile(Number(target.dataset.openProfile));
      return;
    }
    if (target.hasAttribute("data-add-friend")) {
      sendFriendRequest(Number(target.dataset.addFriend));
      return;
    }
    if (target.hasAttribute("data-accept")) {
      acceptRequest(Number(target.dataset.accept));
      return;
    }
    if (target.hasAttribute("data-reject")) {
      rejectRequest(Number(target.dataset.reject));
      return;
    }
    if (target.hasAttribute("data-dm")) {
      startDm(Number(target.dataset.dm));
      return;
    }
    if (target.hasAttribute("data-remove-friend")) {
      const id = Number(target.dataset.removeFriend);
      if (target.dataset.confirm === "1") {
        removeFriend(id);
      } else {
        target.dataset.confirm = "1";
        target.textContent = "再点一次确认删除";
        setTimeout(() => {
          if (target.isConnected) {
            target.dataset.confirm = "0";
            target.textContent = "删除好友";
          }
        }, 3200);
      }
      return;
    }
    if (target.hasAttribute("data-leave-room")) {
      const room = roomOf(Number(target.dataset.leaveRoom));
      if (!room || room.ownerId === activeAccountId) return;
      room.members = room.members.filter((id) => id !== activeAccountId);
      activeConvKey = visibleConversations()[0]?.key || "";
      toast("已退出群聊");
      renderAll();
      return;
    }
    if (target.hasAttribute("data-kick")) {
      const room = roomOf(activeConvKey.startsWith("room:") ? Number(activeConvKey.split(":")[1]) : -1);
      if (!room) return;
      const id = Number(target.dataset.kick);
      room.members = room.members.filter((m) => m !== id);
      toast(`已移除 ${accountName(id)}`);
      renderRoom();
      return;
    }
    if (target.hasAttribute("data-switch")) {
      switchAccount(Number(target.dataset.switch));
      return;
    }
    if (target.hasAttribute("data-create-agent")) {
      renderAccountDetail("form");
      return;
    }
    if (target.hasAttribute("data-cancel-agent")) {
      renderAccountDetail("empty");
      return;
    }
    if (target.hasAttribute("data-copy-key")) {
      copyKey($("#agentKey").textContent);
      return;
    }
    if (target.hasAttribute("data-finish-key")) {
      renderAccountDetail("empty");
      renderAccounts();
      return;
    }
  });

  app.addEventListener("submit", (event) => {
    const invite = event.target.closest("[data-invite-form]");
    if (invite) {
      event.preventDefault();
      const input = $("input", invite);
      const found = lookupAccount(input.value);
      const room = roomOf(activeConvKey.startsWith("room:") ? Number(activeConvKey.split(":")[1]) : -1);
      if (!room) return;
      if (found.error) { toast(found.error); return; }
      if (room.members.includes(found.id)) { toast("对方已经在群里了"); return; }
      room.members.push(found.id);
      input.value = "";
      toast(`已把 ${accountName(found.id)} 拉进群`);
      renderRoom();
      return;
    }

    const agentForm = event.target.closest("#agentForm");
    if (agentForm) {
      event.preventDefault();
      const name = $("#agentName").value.trim();
      if (!name || name.length > 20) {
        $("#agentErr").textContent = "名字要在 1–20 个字之间";
        $("#agentErr").classList.add("is-error");
        $("#agentName").focus();
        return;
      }
      createAgent(name);
      return;
    }

    if (event.target.closest("#addFriendForm")) {
      event.preventDefault();
      const found = lookupAccount($("#addFriendId").value);
      const hint = $("#addFriendHint");
      if (found.error) {
        hint.textContent = found.error;
        hint.classList.add("is-error");
        return;
      }
      hint.classList.remove("is-error");
      hint.textContent = "V1 不做搜人。群成员资料页与账号 ID 是仅有的入口。";
      selectedContact = found.id;
      renderContactDetail(found.id);
      return;
    }

    if (event.target.closest("#createRoomForm")) {
      event.preventDefault();
      const name = $("#roomNameInput").value.trim();
      const memberRaw = $("#roomMemberInput").value.trim();
      const err = $("#roomErr");
      err.classList.remove("is-error");
      err.textContent = "";
      if (!name || name.length > 20) {
        err.textContent = "群名要在 1–20 个字之间";
        err.classList.add("is-error");
        return;
      }
      let memberId = null;
      if (memberRaw) {
        const found = lookupAccount(memberRaw);
        if (found.error) { err.textContent = found.error; err.classList.add("is-error"); return; }
        if (found.id === activeAccountId) { err.textContent = "不能把自己拉进群。"; err.classList.add("is-error"); return; }
        memberId = found.id;
      }
      const id = 30 + rooms.length;
      const room = { id, name, ownerId: activeAccountId, members: [activeAccountId].concat(memberId ? [memberId] : []), mark: name.slice(0, 1) };
      rooms.push(room);
      const key = convKey("room", id);
      conversations.unshift({ key, type: "room", id, time: nowTime(), unread: 0 });
      threads[key] = [{ divider: "今天" }];
      $("#createRoomForm").hidden = true;
      setView("messages");
      selectConversation(key);
      toast(`已建群 ${name}`);
      return;
    }
  });

  $("#addFriendBtn").addEventListener("click", () => {
    const form = $("#addFriendForm");
    form.hidden = !form.hidden;
    if (!form.hidden) $("#addFriendId").focus();
  });
  $("#addFriendCancel").addEventListener("click", () => {
    $("#addFriendForm").hidden = true;
  });
  $("#createRoomBtn").addEventListener("click", () => {
    const form = $("#createRoomForm");
    form.hidden = !form.hidden;
    if (!form.hidden) $("#roomNameInput").focus();
    $("#addFriendForm").hidden = true;
  });
  $("#createRoomCancel").addEventListener("click", () => {
    $("#createRoomForm").hidden = true;
  });

  $("#profileClose").addEventListener("click", closeProfile);
  refs.scrim.addEventListener("click", closeProfile);

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      if (!refs.profileSheet.hidden) { closeProfile(); return; }
      if (view === "messages") {
        app.classList.add("no-info");
        $("#infoBtn").setAttribute("aria-pressed", "false");
      }
    }
  });

  $("#chatReset").addEventListener("click", () => {
    accounts = JSON.parse(JSON.stringify(seedAccounts));
    rooms = JSON.parse(JSON.stringify(seedRooms));
    conversations = JSON.parse(JSON.stringify(seedConvs));
    threads = JSON.parse(JSON.stringify(seedThreads));
    friends = JSON.parse(JSON.stringify(seedFriends));
    incoming = JSON.parse(JSON.stringify(seedIncoming));
    outgoing = {};
    activeAccountId = ME0;
    activeConvKey = "dm:1002";
    convFilter = "all";
    friendsTab = "friends";
    selectedContact = null;
    closeProfile();
    app.classList.remove("no-info");
    $("#infoBtn").setAttribute("aria-pressed", "true");
    refs.msgInput.value = "";
    updateCounter();
    $$(".tab[data-filter]").forEach((tab) => {
      const on = tab.dataset.filter === "all";
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", String(on));
    });
    $$(".tab[data-friends-tab]").forEach((tab) => {
      const on = tab.dataset.friendsTab === "friends";
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", String(on));
    });
    $("#addFriendForm").hidden = true;
    $("#createRoomForm").hidden = true;
    setView("messages");
    renderAll();
  });

  renderAll();
  updateCounter();
})();
