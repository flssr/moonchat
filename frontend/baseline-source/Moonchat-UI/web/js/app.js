/* ============================================================
   Moonchat · 月面登陆
   No dependencies. Vanilla JS, Web Animations + Canvas + WebAudio.
   ============================================================ */
(() => {
  'use strict';

  /* ---------- 0. helpers ---------- */
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const rand = (a, b) => a + Math.random() * (b - a);
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const el = {
    scene: $('#scene'),
    intro: $('.intro'),
    panel: $('#loginForm'),
    email: $('#email'),
    pass: $('#password'),
    fieldEmail: $('#fieldEmail'),
    fieldPass: $('#fieldPass'),
    error: $('#error'),
    eye: $('#eyeBtn'),
    register: $('#registerLink'),
    rocket: $('#rocket'),
    rocketStage: $('#rocketStage'),
    wipe: $('#wipeLayer'),
    leaf: $('#doorLeaf'),
    patch: $('#framePatch'),
    layout: $('.layout'),
    doorway: $('#doorway'),
    enterBtn: $('#enterBtn'),
    moon: $('#moon'),
    skyEl: $('#sky'),
    warp: $('#warp'),
    flash: $('#flash'),
    dust: $('#dust'),
    app: $('#app'),
    frame: $('.app__frame'),
    toast: $('#toast'),
    soundBtn: $('#soundBtn'),
    boot: $('#boot'),
  };

  const params = new URLSearchParams(location.search);
  const jump = params.get('state') || 'login';

  /* ============================================================
     1. sound — tiny synthesised SFX, no assets
     ============================================================ */
  const Sfx = {
    ctx: null,
    master: null,
    on: true,
    noiseBuf: null,

    boot() {
      if (this.ctx) {
        if (this.ctx.state === 'suspended') this.ctx.resume();
        return this.ctx;
      }
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.5;
      this.master.connect(this.ctx.destination);

      const len = this.ctx.sampleRate * 2;
      this.noiseBuf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const data = this.noiseBuf.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
      return this.ctx;
    },

    tone(freq, dur, { type = 'sine', gain = 0.06, to = null, delay = 0 } = {}) {
      if (!this.on || !this.boot()) return;
      const t0 = this.ctx.currentTime + delay;
      const o = this.ctx.createOscillator();
      const g = this.ctx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(freq, t0);
      if (to) o.frequency.exponentialRampToValueAtTime(Math.max(20, to), t0 + dur);
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(gain, t0 + 0.012);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      o.connect(g).connect(this.master);
      o.start(t0);
      o.stop(t0 + dur + 0.05);
    },

    noise(dur, { gain = 0.06, from = 400, to = 1200, q = 1.2, delay = 0, type = 'bandpass' } = {}) {
      if (!this.on || !this.boot()) return;
      const t0 = this.ctx.currentTime + delay;
      const src = this.ctx.createBufferSource();
      src.buffer = this.noiseBuf;
      const f = this.ctx.createBiquadFilter();
      f.type = type;
      f.Q.value = q;
      f.frequency.setValueAtTime(from, t0);
      f.frequency.exponentialRampToValueAtTime(Math.max(40, to), t0 + dur);
      const g = this.ctx.createGain();
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(gain, t0 + 0.05);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      src.connect(f).connect(g).connect(this.master);
      src.start(t0);
      src.stop(t0 + dur + 0.05);
    },

    tick() {
      this.tone(1180, 0.05, { gain: 0.035, to: 780 });
      this.noise(0.03, { gain: 0.02, from: 3000, to: 1800 });
    },
    hover() { this.tone(1560, 0.035, { gain: 0.014, type: 'sine' }); },
    whoosh() {
      this.noise(0.72, { gain: 0.05, from: 260, to: 2200, q: 0.9 });
      this.tone(220, 0.42, { gain: 0.03, to: 90, type: 'sine' });
    },
    thud() {
      this.tone(120, 0.32, { gain: 0.11, to: 48 });
      this.noise(0.18, { gain: 0.05, from: 900, to: 120, type: 'lowpass' });
    },
    zap() {
      this.tone(520, 0.18, { gain: 0.045, to: 1500, type: 'triangle' });
      this.noise(0.2, { gain: 0.03, from: 1800, to: 400 });
    },
    launch() {
      this.noise(2.6, { gain: 0.09, from: 120, to: 900, type: 'lowpass', q: 0.7 });
      this.tone(58, 2.4, { gain: 0.07, to: 34, type: 'sawtooth' });
      this.tone(180, 1.2, { gain: 0.03, to: 420, type: 'sine' });
    },
    chime() {
      this.tone(660, 1.1, { gain: 0.04 });
      this.tone(990, 1.3, { gain: 0.028, delay: 0.11 });
      this.tone(1320, 0.9, { gain: 0.016, delay: 0.2 });
    },
    pop() { this.tone(720, 0.09, { gain: 0.03, to: 980, type: 'triangle' }); },
  };

  el.soundBtn.addEventListener('click', () => {
    Sfx.on = !Sfx.on;
    el.soundBtn.setAttribute('aria-pressed', String(Sfx.on));
    el.soundBtn.title = Sfx.on ? '声音：开' : '声音：关';
    el.soundBtn.querySelector('use').setAttribute('href', Sfx.on ? '#i-sound' : '#i-mute');
    if (Sfx.on) Sfx.tick();
    toast(Sfx.on ? '声音已开启' : '声音已静音');
  });

  /* ============================================================
     2. starfield
     ============================================================ */
  class Starfield {
    constructor(canvas) {
      this.c = canvas;
      this.ctx = canvas.getContext('2d');
      this.dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.stars = [];
      this.meteors = [];
      this.speed = 0;
      this.targetSpeed = 0;
      this.px = 0; this.py = 0;
      this.tx = 0; this.ty = 0;
      this.nextMeteor = performance.now() + 3000;
      this.resize();
      window.addEventListener('resize', () => this.resize(), { passive: true });
      window.addEventListener('pointermove', (e) => {
        this.tx = (e.clientX / innerWidth - 0.5) * 2;
        this.ty = (e.clientY / innerHeight - 0.5) * 2;
      }, { passive: true });
      this.loop = this.loop.bind(this);
      requestAnimationFrame(this.loop);
    }

    makeStar() {
      const d = Math.random();
      return {
        x: Math.random(),
        y: Math.random(),
        r: d > 0.94 ? rand(1.4, 2.3) : d > 0.7 ? rand(0.9, 1.4) : rand(0.35, 0.9),
        a: rand(0.25, 0.95),
        tw: rand(0.4, 2.1),
        ph: rand(0, Math.PI * 2),
        depth: rand(0.25, 1),
        warm: Math.random() > 0.86,
      };
    }

    resize() {
      const w = innerWidth, h = innerHeight;
      this.w = w; this.h = h;
      this.c.width = Math.round(w * this.dpr);
      this.c.height = Math.round(h * this.dpr);
      this.c.style.width = w + 'px';
      this.c.style.height = h + 'px';
      this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      const n = Math.round(clamp((w * h) / 8600, 90, 300));
      this.stars = Array.from({ length: n }, () => this.makeStar());
    }

    spawnMeteor() {
      const fromLeft = Math.random() > 0.45;
      this.meteors.push({
        x: fromLeft ? rand(-0.1, 0.5) : rand(0.7, 1.1),
        y: rand(-0.1, 0.45),
        vx: fromLeft ? rand(0.55, 0.95) : rand(-0.95, -0.55),
        vy: rand(0.3, 0.6),
        life: 1,
        len: rand(0.12, 0.24),
      });
    }

    loop(now) {
      const ctx = this.ctx;
      const w = this.w, h = this.h;
      const t = now / 1000;

      this.px += (this.tx * 16 - this.px) * 0.045;
      this.py += (this.ty * 16 - this.py) * 0.045;
      this.speed += (this.targetSpeed - this.speed) * 0.035;

      ctx.clearRect(0, 0, w, h);

      const cx = w / 2, cy = h / 2;

      for (const s of this.stars) {
        const x = s.x * w + this.px * s.depth;
        const y = s.y * h + this.py * s.depth;
        const twinkle = 0.62 + 0.38 * Math.sin(t * s.tw + s.ph);
        const alpha = clamp(s.a * twinkle, 0, 1);

        if (this.speed > 0.03) {
          const dx = x - cx, dy = y - cy;
          const d = Math.hypot(dx, dy) || 1;
          const len = this.speed * (140 + 240 * s.depth);
          const g = ctx.createLinearGradient(x, y, x + (dx / d) * len, y + (dy / d) * len);
          g.addColorStop(0, `rgba(210,232,255,${alpha * 0.85})`);
          g.addColorStop(1, 'rgba(210,232,255,0)');
          ctx.strokeStyle = g;
          ctx.lineWidth = s.r;
          ctx.beginPath();
          ctx.moveTo(x, y);
          ctx.lineTo(x + (dx / d) * len, y + (dy / d) * len);
          ctx.stroke();
        } else {
          const c = s.warm ? '255,236,205' : '224,238,255';
          if (s.r > 1.3) {
            const g = ctx.createRadialGradient(x, y, 0, x, y, s.r * 5);
            g.addColorStop(0, `rgba(${c},${alpha})`);
            g.addColorStop(0.35, `rgba(${c},${alpha * 0.28})`);
            g.addColorStop(1, `rgba(${c},0)`);
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(x, y, s.r * 5, 0, Math.PI * 2);
            ctx.fill();
          }
          ctx.fillStyle = `rgba(${c},${alpha})`;
          ctx.beginPath();
          ctx.arc(x, y, s.r, 0, Math.PI * 2);
          ctx.fill();
        }
      }

      // shooting stars
      if (now > this.nextMeteor && this.speed < 0.1) {
        this.spawnMeteor();
        this.nextMeteor = now + rand(4500, 11000);
      }
      for (let i = this.meteors.length - 1; i >= 0; i--) {
        const m = this.meteors[i];
        m.x += m.vx * 0.012;
        m.y += m.vy * 0.012;
        m.life -= 0.008;
        if (m.life <= 0 || m.x < -0.3 || m.x > 1.3 || m.y > 1.2) { this.meteors.splice(i, 1); continue; }
        const x = m.x * w, y = m.y * h;
        const tailX = x - m.vx * w * m.len, tailY = y - m.vy * h * m.len;
        const g = ctx.createLinearGradient(x, y, tailX, tailY);
        g.addColorStop(0, `rgba(255,255,255,${0.85 * m.life})`);
        g.addColorStop(0.3, `rgba(180,215,255,${0.35 * m.life})`);
        g.addColorStop(1, 'rgba(180,215,255,0)');
        ctx.strokeStyle = g;
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(tailX, tailY);
        ctx.stroke();
      }

      requestAnimationFrame(this.loop);
    }
  }

  const sky = new Starfield($('#stars'));

  /* ============================================================
     3. particle bursts
     ============================================================ */
  function burst(x, y, opts = {}) {
    if (reduceMotion) return;
    const {
      count = 16,
      colors = ['#c9e9ff', '#8fd0ff', '#ffffff'],
      spread = 70,
      size = 5,
      duration = 900,
      drift = 0,
    } = opts;
    for (let i = 0; i < count; i++) {
      const p = document.createElement('span');
      const color = colors[(Math.random() * colors.length) | 0];
      const s = size * rand(0.35, 1.15);
      p.style.cssText = `position:fixed;left:${x}px;top:${y}px;width:${s}px;height:${s}px;border-radius:50%;` +
        `background:${color};box-shadow:0 0 12px ${color};pointer-events:none;z-index:55;opacity:1;will-change:transform,opacity`;
      document.body.appendChild(p);
      const ang = Math.random() * Math.PI * 2;
      const dist = spread * rand(0.25, 1);
      const dur = duration * rand(0.65, 1.25);
      const anim = p.animate([
        { transform: 'translate(-50%,-50%) scale(1)', opacity: 1 },
        {
          transform: `translate(calc(-50% + ${Math.cos(ang) * dist}px), calc(-50% + ${Math.sin(ang) * dist + drift}px)) scale(.15)`,
          opacity: 0,
        },
      ], { duration: dur, easing: 'cubic-bezier(.18,.7,.3,1)', fill: 'forwards' });
      anim.onfinish = () => p.remove();
    }
  }

  function smoke(x, y, count = 14) {
    if (reduceMotion) return;
    for (let i = 0; i < count; i++) {
      const p = document.createElement('span');
      const s = rand(26, 70);
      p.style.cssText = `position:fixed;left:${x + rand(-30, 30)}px;top:${y}px;width:${s}px;height:${s}px;border-radius:50%;` +
        'background:radial-gradient(circle, rgba(215,225,240,.5), rgba(160,180,210,0) 70%);' +
        'pointer-events:none;z-index:54;filter:blur(3px);will-change:transform,opacity';
      document.body.appendChild(p);
      p.animate([
        { transform: 'translate(-50%,-50%) scale(.4)', opacity: .85 },
        {
          transform: `translate(calc(-50% + ${rand(-150, 150)}px), calc(-50% + ${rand(40, 130)}px)) scale(${rand(1.1, 2)})`,
          opacity: 0,
        },
      ], { duration: rand(1100, 1900), easing: 'cubic-bezier(.2,.6,.3,1)', fill: 'forwards' }).onfinish = () => p.remove();
    }
  }

  /* a soft shockwave where the ship slips into the moon */
  function moonImpact(x, y) {
    if (reduceMotion) return;
    const ring = document.createElement('span');
    ring.style.cssText =
      `position:fixed;left:${x}px;top:${y}px;width:64px;height:64px;margin:-32px 0 0 -32px;` +
      'border-radius:50%;border:2px solid rgba(255,255,255,.85);' +
      'box-shadow:0 0 40px rgba(190,225,255,.85), inset 0 0 40px rgba(200,235,255,.5);' +
      'pointer-events:none;z-index:46;will-change:transform,opacity';
    document.body.appendChild(ring);
    ring.animate([
      { transform: 'scale(.15)', opacity: 1 },
      { transform: 'scale(3.6)', opacity: 0 },
    ], { duration: 820, easing: 'cubic-bezier(.16,.7,.3,1)', fill: 'forwards' }).onfinish = () => ring.remove();

    burst(x, y, { count: 20, colors: ['#ffffff', '#dcebff', '#ffe9c9'], spread: 88, size: 3.5, duration: 850 });
  }

  /* ============================================================
     4. toast
     ============================================================ */
  let toastTimer;
  function toast(msg, ms = 2800) {
    el.toast.textContent = msg;
    el.toast.classList.add('is-on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.toast.classList.remove('is-on'), ms);
  }

  /* ============================================================
     5. login choreography
     ============================================================ */
  const setPhase = (p) => { el.scene.dataset.phase = p; };

  let busy = false;
  const emailOK = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v.trim());

  function syncPanel() {
    const e = el.email.value.trim();
    const p = el.pass.value;
    el.fieldEmail.classList.toggle('is-ok', emailOK(e));
    el.fieldPass.classList.toggle('is-ok', p.length >= 4);
    el.panel.classList.toggle('is-ready', emailOK(e) && p.length >= 4);
  }

  el.email.addEventListener('input', () => { el.error.classList.remove('is-on'); syncPanel(); });
  el.pass.addEventListener('input', () => { el.error.classList.remove('is-on'); syncPanel(); });

  el.eye.addEventListener('click', (e) => {
    e.stopPropagation();
    const on = el.fieldPass.classList.toggle('is-reveal');
    el.pass.type = on ? 'text' : 'password';
    el.eye.setAttribute('aria-label', on ? '隐藏密码' : '显示密码');
    el.pass.focus({ preventScroll: true });
    Sfx.tick();
  });

  // clicking anywhere on the field focuses its input
  $$('.field').forEach((f) => {
    f.addEventListener('click', (e) => {
      if (e.target.closest('button')) return;
      const input = f.querySelector('input');
      input.focus({ preventScroll: true });
    });
  });

  function fail(msg, field) {
    el.error.textContent = msg;
    el.error.classList.add('is-on');
    if (field) {
      field.classList.remove('is-bad');
      void field.offsetWidth;
      field.classList.add('is-bad');
      field.querySelector('input').focus({ preventScroll: true });
    }
    Sfx.tone(180, 0.16, { gain: 0.05, to: 120, type: 'triangle' });
  }

  el.panel.addEventListener('submit', (e) => {
    e.preventDefault();
    if (busy) return;
    const email = el.email.value.trim();
    const pass = el.pass.value;
    if (!email) return fail('请输入邮箱，宇航员。', el.fieldEmail);
    if (!emailOK(email)) return fail('邮箱格式好像不太对，检查一下 @ 前后。', el.fieldEmail);
    if (!pass) return fail('请输入密码。', el.fieldPass);
    if (pass.length < 4) return fail('密码至少需要 4 位。', el.fieldPass);
    board();
  });

  el.register.addEventListener('click', (e) => {
    e.preventDefault();
    Sfx.pop();
    toast('注册通道正在铺设中，先用任意邮箱登舱吧 ✦', 3200);
  });

  async function board() {
    busy = true;
    el.error.classList.remove('is-on');
    setPhase('boarding');
    Sfx.tick();
    Sfx.whoosh();

    const fields = [el.fieldEmail, el.fieldPass];
    const rocketBox = el.rocket.getBoundingClientRect();
    const target = {
      x: rocketBox.left + rocketBox.width * 0.6505,
      y: rocketBox.top + rocketBox.height * 0.4185,
    };

    const clones = fields.map((f) => {
      const r = f.getBoundingClientRect();
      const c = f.cloneNode(true);
      c.classList.add('flyer');
      c.style.left = r.left + 'px';
      c.style.top = r.top + 'px';
      c.style.width = r.width + 'px';
      c.style.height = r.height + 'px';
      document.body.appendChild(c);
      return { node: c, rect: r };
    });

    fields.forEach((f) => { f.style.visibility = 'hidden'; });
    el.intro.classList.add('is-gone');

    await sleep(120);

    const flights = clones.map(({ node, rect }, i) => {
      const dx = target.x - (rect.left + rect.width / 2);
      const dy = target.y - (rect.top + rect.height / 2);
      return node.animate([
        { transform: 'translate(0,0) scale(1) rotate(0deg)', opacity: 1 },
        {
          offset: 0.55,
          transform: `translate(${dx * 0.52}px, ${dy * 0.42}px) scale(.62) rotate(${i ? 6 : -6}deg)`,
          opacity: 1,
        },
        {
          transform: `translate(${dx}px, ${dy}px) scale(.16) rotate(${i ? 14 : -12}deg)`,
          opacity: 0.85,
        },
      ], {
        duration: reduceMotion ? 300 : 900,
        delay: reduceMotion ? 0 : i * 110,
        easing: 'cubic-bezier(.42,0,.2,1)',
        fill: 'forwards',
      });
    });

    await Promise.all(flights.map((a) => a.finished.catch(() => {})));
    await sleep(180);

    burst(target.x, target.y, { count: 22, spread: 58, size: 4.5, duration: 800 });
    Sfx.zap();
    clones.forEach(({ node }) => node.remove());
    fields.forEach((f) => { f.style.visibility = ''; });

    await sleep(260);
    closeDoor();
  }

  async function closeDoor() {
    setPhase('closing');
    Sfx.whoosh();

    // drift the rocket to centre stage now that the form is gone
    const introW = el.intro.getBoundingClientRect().width;
    const gap = parseFloat(getComputedStyle(el.layout).columnGap) || 0;
    if (innerWidth > 940) el.scene.style.setProperty('--shift', `${Math.round((introW + gap) / 2)}px`);

    // 1) the door leaf swings back on its hinge and folds out of sight
    const leaf = el.leaf;
    leaf.animate([
      { transform: 'perspective(1100px) rotateY(0deg)', opacity: 1 },
      { offset: 0.6, transform: 'perspective(1100px) rotateY(-62deg)', opacity: 1 },
      { transform: 'perspective(1100px) rotateY(-92deg)', opacity: 0 },
    ], {
      duration: reduceMotion ? 160 : 420,
      easing: 'cubic-bezier(.45,.02,.55,1)',
      fill: 'forwards',
    });

    // 2) the closed door sweeps across the doorway from the hinge side
    const from = 'inset(26.5% 21.5% 41.4% 76.8%)';
    const to = 'inset(26.5% 21.5% 41.4% 53.3%)';

    await sleep(reduceMotion ? 60 : 300);

    const anim = el.wipe.animate([
      { clipPath: from },
      { offset: 0.7, clipPath: 'inset(26.5% 21.5% 41.4% 53.6%)' },
      { clipPath: to },
    ], {
      duration: reduceMotion ? 240 : 680,
      easing: 'cubic-bezier(.55,.02,.25,1)',
      fill: 'forwards',
    });

    // 3) once the leaf is out of the way, repaint the hull edge it was hiding
    setTimeout(() => {
      el.patch.animate([{ opacity: 0 }, { opacity: 1 }], {
        duration: 320, easing: 'ease-out', fill: 'forwards',
      });
    }, reduceMotion ? 120 : 460);

    await sleep(reduceMotion ? 100 : 420);
    const r = el.doorway.getBoundingClientRect();
    burst(r.left + r.width / 2, r.top + r.height * 0.5, {
      count: 12, colors: ['#dff0ff', '#a9d6ff'], spread: 46, size: 3.5, duration: 700,
    });

    await anim.finished.catch(() => {});
    el.wipe.style.clipPath = to;

    // a little mechanical thud
    el.rocket.animate([
      { transform: 'translateY(0) scale(1)' },
      { transform: 'translateY(0.6%) scale(1.004, .995)' },
      { transform: 'translateY(0) scale(1)' },
    ], { duration: 420, easing: 'cubic-bezier(.3,1.6,.5,1)' });
    Sfx.thud();

    await sleep(420);
    setPhase('ready');
    busy = false;
    Sfx.chime();
    burst(rocketBoxCenter().x, rocketBoxCenter().y, {
      count: 10, colors: ['#ffd9df', '#ff8fa3'], spread: 80, size: 3, duration: 900,
    });
  }

  function rocketBoxCenter() {
    const b = el.enterBtn.getBoundingClientRect();
    return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
  }

  el.enterBtn.addEventListener('click', () => {
    if (busy) return;
    launch();
  });

  async function launch() {
    busy = true;
    document.body.classList.add('is-launching');
    setPhase('launch');
    Sfx.launch();

    const b = el.enterBtn.getBoundingClientRect();
    burst(b.left + b.width / 2, b.top + b.height / 2, { count: 16, spread: 60, size: 4, duration: 600 });

    const stage = el.rocketStage.getBoundingClientRect();
    smoke(stage.left + stage.width / 2, stage.bottom - stage.height * 0.04, 18);

    el.rocket.style.animation = 'none';

    // ignition: the whole ship shudders on the pad before it lets go
    el.rocket.animate([
      { transform: 'translate3d(0,0,0) rotate(0deg)' },
      { transform: 'translate3d(-2px,1px,0) rotate(-.15deg)' },
      { transform: 'translate3d(2px,-1px,0) rotate(.15deg)' },
      { transform: 'translate3d(-1.5px,.5px,0) rotate(-.1deg)' },
      { transform: 'translate3d(0,0,0) rotate(0deg)' },
    ], { duration: 90, iterations: 5, easing: 'linear' });

    el.skyEl.animate([
      { transform: 'translate3d(0,0,0)' },
      { transform: 'translate3d(-3px,2px,0)' },
      { transform: 'translate3d(2px,-3px,0)' },
      { transform: 'translate3d(-2px,-1px,0)' },
      { transform: 'translate3d(0,0,0)' },
    ], { duration: 460, easing: 'ease-out' });

    await sleep(reduceMotion ? 60 : 240);

    // liftoff: vertical climb, pitch over, then spiral down into the moon
    // until the ship is a speck of light and disappears.
    const moonTarget = { x: innerWidth * 0.6, y: innerHeight * 0.32 };
    const rb = el.rocket.getBoundingClientRect();
    const rc = { x: rb.left + rb.width / 2, y: rb.top + rb.height / 2 };
    const endDx = moonTarget.x - rc.x;
    const endDy = moonTarget.y - rc.y - rb.height * 0.08; // pivot sits at 58% height
    const P = (fx, fy) => `translate3d(${(endDx * fx).toFixed(1)}px, ${(endDy * fy).toFixed(1)}px, 0)`;

    el.rocket.style.transformOrigin = '50% 58%';
    const flight = el.rocket.animate([
      {
        offset: 0,
        transform: `translate3d(0px, 0px, 0) rotate(0deg) scale(1)`,
        opacity: 1,
        easing: 'cubic-bezier(.35, .02, .7, .6)',
      },
      {
        offset: 0.08,
        transform: `translate3d(-0.4vw, -1.6vh, 0) rotate(-3deg) scale(1.015)`,
        opacity: 1,
        easing: 'cubic-bezier(.45, .05, .55, .95)',
      },
      {
        offset: 0.2,
        transform: `${P(0.02, 0.06)} rotate(-1.6deg) scale(1.01)`,
        opacity: 1,
        easing: 'cubic-bezier(.4, .05, .6, .95)',
      },
      {
        offset: 0.34,
        transform: `${P(0.07, 0.17)} rotate(7deg) scale(.95)`,
        opacity: 1,
        easing: 'cubic-bezier(.4, .05, .6, .95)',
      },
      {
        offset: 0.5,
        transform: `${P(0.16, 0.33)} rotate(16deg) scale(.84)`,
        opacity: 1,
        easing: 'cubic-bezier(.4, .02, .6, .98)',
      },
      {
        offset: 0.65,
        transform: `${P(0.3, 0.52)} rotate(25deg) scale(.68)`,
        opacity: 1,
        easing: 'cubic-bezier(.4, 0, .6, 1)',
      },
      {
        offset: 0.79,
        transform: `${P(0.5, 0.71)} rotate(34deg) scale(.5)`,
        opacity: 1,
        easing: 'cubic-bezier(.35, 0, .6, 1)',
      },
      {
        offset: 0.9,
        transform: `${P(0.74, 0.87)} rotate(44deg) scale(.3)`,
        opacity: .92,
        easing: 'cubic-bezier(.3, 0, .6, 1)',
      },
      {
        offset: 0.97,
        transform: `${P(0.94, 0.97)} rotate(54deg) scale(.1)`,
        opacity: .55,
      },
      {
        offset: 1,
        transform: `translate3d(${endDx.toFixed(1)}px, ${endDy.toFixed(1)}px, 0) rotate(62deg) scale(.015)`,
        opacity: 0,
      },
    ], {
      duration: reduceMotion ? 600 : 2700,
      fill: 'forwards',
    });

    el.warp.classList.add('is-on');
    sky.targetSpeed = 1;

    // camera turns after the ship, the moon swells to fill the view
    const m = el.moon.getBoundingClientRect();
    const dx = moonTarget.x - (m.left + m.width / 2);
    const dy = moonTarget.y - (m.top + m.height / 2);
    el.moon.style.transform = `translate(${dx}px, ${dy}px) scale(2.9)`;
    el.moon.style.opacity = '1';

    // warp + bloom follow the same vanishing point
    el.warp.style.setProperty('--wx', '58%');
    el.warp.style.setProperty('--wy', '40%');
    el.flash.style.setProperty('--fx', '60%');
    el.flash.style.setProperty('--fy', '32%');

    await sleep(reduceMotion ? 250 : 1200);
    smoke(stage.left + stage.width / 2, stage.bottom, 8);

    await sleep(reduceMotion ? 200 : 1330);
    // the ship is a speck of light now — it touches the moon and is gone
    moonImpact(moonTarget.x, moonTarget.y);
    Sfx.zap();

    await sleep(reduceMotion ? 60 : 160);
    el.flash.classList.add('is-on');
    Sfx.whoosh();

    // the moon opens into the portal we dive through
    el.app.style.setProperty('--ox', '60%');
    el.app.style.setProperty('--oy', '32%');

    await sleep(reduceMotion ? 120 : 360);
    el.scene.classList.add('is-gone');
    el.app.classList.add('is-on');
    el.app.setAttribute('aria-hidden', 'false');
    document.body.classList.add('in-app');
    el.moon.style.opacity = '0';
    sky.targetSpeed = 0;
    el.flash.classList.remove('is-on');

    if (!reduceMotion) {
      const rows = $$('.conv, .msg');
      rows.forEach((r, i) => {
        r.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'none' }], {
          duration: 500, delay: 380 + i * 24, easing: 'cubic-bezier(.16,.84,.28,1)', fill: 'both',
        });
      });
    }

    await sleep(520);
    Sfx.chime();
    startChatIntro();
  }

  /* ============================================================
     6. chat data
     ============================================================ */
  const emojiPool = ['🚀', '🌙', '✨', '🛰️', '🌌', '☄️', '👽', '🌍', '🔥', '💫', '🎧', '☕', '🪐', '💬', '😄', '😴', '🤝', '🌠'];

  const conversations = [
    {
      id: 'luna', name: '月面基地 · Luna', short: 'Luna', emoji: '🌙', a1: '#3f5f9e', a2: '#1d2c4f',
      time: '21:04', preview: '欢迎登舰，舱内一切就绪', unread: 0, group: false,
      status: '在线 · 第 3 号舷窗',
      messages: [
        { from: 'them', text: '舱门已关闭，欢迎登舰 🚀', time: '21:04' },
        { from: 'them', media: 'assets/rocket-closed.png', cap: '你的座驾已就位', time: '21:04' },
        { from: 'me', text: '终于上来了，外面星星真多。', time: '21:05' },
        { from: 'them', text: '这里是月面基地 A-07，你的频道已经接入全站。\n想聊什么都可以，我在。', time: '21:05' },
      ],
      replies: [
        '收到，信号很清楚 📡',
        '月面这边一切正常，窗外的地球正好升起来。',
        '那就说定了，环形山见 🌑',
        '我把频道调到最佳了，继续说。',
        '嗯，我在听。',
      ],
    },
    {
      id: 'cafe', name: '轨道咖啡屋', short: '咖啡屋', emoji: '☕', a1: '#8a5a3c', a2: '#3a2418',
      time: '20:41', preview: '阿澈：今晚的月食别错过', unread: 2, group: true,
      status: '12 人在线 · 环形山露台',
      messages: [
        { from: 'them', name: '阿澈', text: '今晚 23:40 有月食，露台的位子我占了三个。', time: '20:38' },
        { from: 'them', name: '小满', text: '带了两罐冰的月尘汽水 🥤', time: '20:40' },
        { from: 'them', name: '阿澈', text: '今晚的月食别错过', time: '20:41' },
      ],
      replies: ['给我留一个位子！', '我带点吃的过去 🍪', '月尘汽水听起来很不错。'],
    },
    {
      id: 'apollo', name: '阿波罗计划', short: '阿波罗', emoji: '🛰️', a1: '#2f6b6a', a2: '#123033',
      time: '19:12', preview: '第 3 次对接演练已排期', unread: 0, group: true,
      status: '8 人在线 · 任务频道',
      messages: [
        { from: 'them', name: '控制台', text: '第 3 次对接演练已排期：明日 09:00（月面时间）。', time: '19:12' },
        { from: 'me', text: '收到，我会提前 20 分钟进舱。', time: '19:20' },
      ],
      replies: ['演练流程已同步到你的终端。', '注意检查氧气循环，上次有点抖。'],
    },
    {
      id: 'radio', name: '星尘电台', short: '星尘', emoji: '📻', a1: '#5b4a8a', a2: '#241c3d',
      time: '昨天', preview: '新一期：低频宇宙', unread: 0, group: false,
      status: '正在广播 · 88.4 MHz',
      messages: [
        { from: 'them', text: '新一期《低频宇宙》上线了，适合在舱里发呆的时候听。', time: '昨天 22:10' },
        { from: 'them', text: '这期的背景音是我在月背录的风。', time: '昨天 22:11' },
      ],
      replies: ['正在听，风的声音很干净。', '下一期想听地球的海。'],
    },
    {
      id: 'neo', name: 'Neo', short: 'Neo', emoji: '🌠', a1: '#7a3b5c', a2: '#2b1526',
      time: '昨天', preview: '在吗？', unread: 0, group: false,
      status: '离开 · 2 小时前',
      messages: [
        { from: 'them', text: '在吗？', time: '昨天 18:02' },
        { from: 'me', text: '刚回来，怎么了？', time: '昨天 18:40' },
      ],
      replies: ['没什么，就是想找个人说说话。', '你那边能看到地球吗？'],
    },
    {
      id: 'weather', name: '月面天气', short: '天气', emoji: '⛅', a1: '#3a6a86', a2: '#152c3a',
      time: '周一', preview: '今日无尘暴，适合出舱', unread: 0, group: false,
      status: '自动播报 · 每日 06:00',
      messages: [
        { from: 'them', text: '今日无尘暴，能见度 18 km，适合出舱。', time: '周一 06:00' },
        { from: 'them', text: '夜间最低 -173°C，记得把加热开到 3 档。', time: '周一 06:00' },
      ],
      replies: ['收到，今天出门走走。', '帮我记一下明天的天气。'],
    },
  ];

  let activeId = 'luna';
  let filter = 'all';
  let query = '';

  const convList = $('#convList');
  const msgList = $('#msgList');

  function avatarStyle(c) {
    return `--a1:${c.a1};--a2:${c.a2}`;
  }

  function renderConvs() {
    convList.textContent = '';
    const list = conversations.filter((c) => {
      if (filter === 'unread' && !c.unread) return false;
      if (filter === 'group' && !c.group) return false;
      if (query && !(c.name + c.preview).toLowerCase().includes(query)) return false;
      return true;
    });

    if (!list.length) {
      const empty = document.createElement('p');
      empty.className = 'demo';
      empty.style.cssText = 'text-align:center;padding:36px 0;';
      empty.textContent = '没有找到相关的频道';
      convList.appendChild(empty);
      return;
    }

    list.forEach((c) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'conv' + (c.id === activeId ? ' is-active' : '');
      b.innerHTML = `
        <span class="avatar" style="${avatarStyle(c)}">${c.emoji}</span>
        <span class="conv__main">
          <span class="conv__name"><b>${c.name}</b></span>
          <span class="conv__preview">${c.preview}</span>
        </span>
        <span class="conv__side">
          <span class="conv__time">${c.time}</span>
          ${c.unread ? `<span class="badge">${c.unread}</span>` : ''}
        </span>`;
      b.addEventListener('click', () => selectConv(c.id));
      convList.appendChild(b);
    });
    $('#convCount').textContent = String(list.length);
  }

  function bubbleNode(m, c) {
    const row = document.createElement('div');
    row.className = 'msg' + (m.from === 'me' ? ' msg--me' : '');

    const av = document.createElement('span');
    av.className = 'avatar';
    av.style.cssText = avatarStyle(c);
    av.textContent = c.emoji;
    if (m.from === 'me') {
      av.style.cssText = '--a1:#f6d9a8;--a2:#e0aa6e';
      av.textContent = '你';
      av.style.fontSize = '12px';
      av.style.fontWeight = '600';
      av.style.color = '#22160a';
    }
    row.appendChild(av);

    const col = document.createElement('div');
    col.className = 'msg__col';

    if (m.name) {
      const n = document.createElement('span');
      n.className = 'msg__name';
      n.textContent = m.name;
      col.appendChild(n);
    }

    const bubble = document.createElement('div');
    if (m.media) {
      bubble.className = 'bubble bubble--media';
      const img = document.createElement('img');
      img.src = m.media;
      img.alt = m.cap || '图片';
      img.loading = 'lazy';
      bubble.appendChild(img);
      if (m.cap) {
        const cap = document.createElement('div');
        cap.className = 'cap';
        cap.innerHTML = '<svg class="ico" style="font-size:13px"><use href="#i-image"/></svg>';
        cap.appendChild(document.createTextNode(m.cap));
        bubble.appendChild(cap);
      }
    } else {
      bubble.className = 'bubble';
      bubble.textContent = m.text;
    }
    col.appendChild(bubble);

    const meta = document.createElement('div');
    meta.className = 'msg__meta';
    meta.innerHTML = `<span>${m.time || ''}</span>` +
      (m.from === 'me' ? '<svg class="ico"><use href="#i-check"/></svg><svg class="ico" style="margin-left:-8px"><use href="#i-check"/></svg>' : '');
    col.appendChild(meta);

    row.appendChild(col);
    return row;
  }

  function renderMessages(id) {
    const c = conversations.find((x) => x.id === id);
    if (!c) return;
    msgList.textContent = '';
    const day = document.createElement('div');
    day.className = 'day';
    day.innerHTML = '<span>今天 · 登舱第 1 天</span>';
    msgList.appendChild(day);
    c.messages.forEach((m) => msgList.appendChild(bubbleNode(m, c)));
    scrollBottom();
  }

  function scrollBottom() {
    requestAnimationFrame(() => {
      msgList.scrollTop = msgList.scrollHeight;
    });
  }

  function selectConv(id) {
    activeId = id;
    const c = conversations.find((x) => x.id === id);
    if (!c) return;
    c.unread = 0;
    $('#roomName').textContent = c.name;
    $('#roomAvatar').textContent = c.emoji;
    $('#roomAvatar').style.cssText = avatarStyle(c);
    $('#roomStatus').innerHTML = `<span class="status-dot"></span>${c.status}`;
    $('#infoAvatar').textContent = c.emoji;
    $('#infoAvatar').style.cssText = avatarStyle(c);
    $('#infoName').textContent = c.short;
    $('#msgInput').placeholder = '发一条消息给 ' + c.short + '…';
    renderConvs();
    renderMessages(id);
    Sfx.tick();
  }

  convList.addEventListener('click', (e) => {
    if (!e.target.closest('.conv')) return;
  });

  $$('.tab').forEach((t) => {
    t.addEventListener('click', () => {
      $$('.tab').forEach((x) => x.classList.remove('is-active'));
      t.classList.add('is-active');
      filter = t.dataset.filter;
      renderConvs();
      Sfx.tick();
    });
  });

  $('#searchInput').addEventListener('input', (e) => {
    query = e.target.value.trim().toLowerCase();
    renderConvs();
  });

  /* composer */
  const input = $('#msgInput');
  const sendBtn = $('#sendBtn');

  function grow() {
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, 132) + 'px';
    sendBtn.disabled = !input.value.trim();
  }
  input.addEventListener('input', grow);

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  });
  sendBtn.addEventListener('click', send);

  let typingEl = null;
  function showTyping() {
    if (typingEl) return;
    const c = conversations.find((x) => x.id === activeId);
    const row = document.createElement('div');
    row.className = 'typing';
    row.innerHTML = `<span class="avatar" style="${avatarStyle(c)}">${c.emoji}</span>
      <span class="typing__bubble"><i></i><i></i><i></i></span>`;
    msgList.appendChild(row);
    typingEl = row;
    scrollBottom();
  }
  function hideTyping() {
    if (!typingEl) return;
    typingEl.remove();
    typingEl = null;
  }

  async function send() {
    const text = input.value.trim();
    if (!text) return;
    const c = conversations.find((x) => x.id === activeId);
    const m = { from: 'me', text, time: new Date().toTimeString().slice(0, 5) };
    c.messages.push(m);
    msgList.appendChild(bubbleNode(m, c));
    c.preview = text;
    c.time = m.time;
    input.value = '';
    grow();
    scrollBottom();
    Sfx.pop();

    await sleep(420);
    showTyping();
    await sleep(rand(900, 1600));
    hideTyping();
    const reply = c.replies[(Math.random() * c.replies.length) | 0];
    const rm = { from: 'them', text: reply, time: new Date().toTimeString().slice(0, 5) };
    c.messages.push(rm);
    c.preview = reply;
    msgList.appendChild(bubbleNode(rm, c));
    scrollBottom();
    Sfx.tick();
  }

  /* emoji popover */
  const emojiPop = $('#emojiPop');
  emojiPool.forEach((e) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = e;
    b.addEventListener('click', () => {
      input.value += e;
      input.focus();
      grow();
      Sfx.pop();
    });
    emojiPop.appendChild(b);
  });
  $('#emojiBtn').addEventListener('click', (e) => {
    e.stopPropagation();
    emojiPop.hidden = !emojiPop.hidden;
    Sfx.tick();
  });
  document.addEventListener('click', (e) => {
    if (!emojiPop.hidden && !e.target.closest('#emojiPop') && !e.target.closest('#emojiBtn')) emojiPop.hidden = true;
  });

  /* info panel */
  $('#infoBtn').addEventListener('click', () => {
    const hidden = el.frame.classList.toggle('is-narrow');
    $('#infoBtn').classList.toggle('is-active', !hidden);
    Sfx.tick();
  });
  $('#infoClose').addEventListener('click', () => {
    el.frame.classList.add('is-narrow');
    $('#infoBtn').classList.remove('is-active');
    Sfx.tick();
  });

  $$('.switch').forEach((s) => s.parentElement.addEventListener('click', () => {
    s.classList.toggle('is-on');
    Sfx.tick();
  }));

  $$('.rail__btn').forEach((b) => b.addEventListener('click', () => {
    if (b.id === 'replayBtn') return;
    $$('.rail__btn').forEach((x) => x.classList.remove('is-active'));
    b.classList.add('is-active');
    Sfx.tick();
  }));

  $('#newChatBtn').addEventListener('click', () => {
    Sfx.pop();
    toast('新的月面频道正在铺设中 ✦');
  });

  $('#replayBtn').addEventListener('click', () => {
    document.body.style.transition = 'opacity .5s';
    document.body.style.opacity = '0';
    setTimeout(() => { location.href = location.pathname; }, 480);
  });

  /* first message after landing */
  function startChatIntro() {
    setTimeout(() => {
      showTyping();
      setTimeout(() => {
        hideTyping();
        const c = conversations.find((x) => x.id === activeId);
        const m = { from: 'them', text: '先随便逛逛吧，我在 3 号舷窗等你 🌙', time: new Date().toTimeString().slice(0, 5) };
        c.messages.push(m);
        msgList.appendChild(bubbleNode(m, c));
        scrollBottom();
        Sfx.tick();
      }, 1500);
    }, 900);
  }

  /* ============================================================
     7. boot
     ============================================================ */
  function bootSequence() {
    syncPanel();
    renderConvs();
    renderMessages(activeId);
    grow();

    const imgs = ['assets/rocket-open.png', 'assets/rocket-closed.png', 'assets/rocket-launch.png'];
    const preload = Promise.all(imgs.map((src) => new Promise((res) => {
      const i = new Image();
      i.onload = i.onerror = () => res();
      i.src = src;
    })));

    const fonts = document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();

    Promise.race([Promise.all([preload, fonts]), sleep(1800)]).then(async () => {
      await sleep(220);
      document.body.classList.add('is-ready');
      el.boot.setAttribute('aria-hidden', 'true');

      if (jump === 'chat') {
        el.scene.style.display = 'none';
        el.app.style.animation = 'none';
        el.app.style.clipPath = 'none';
        el.app.classList.add('is-on');
        el.app.setAttribute('aria-hidden', 'false');
        document.body.classList.add('in-app');
      } else if (jump === 'ready') {
        el.intro.classList.add('is-gone');
        el.leaf.style.opacity = '0';
        el.patch.style.opacity = '1';
        el.wipe.style.clipPath = 'inset(26.5% 21.5% 41.4% 53.3%)';
        if (innerWidth > 940) {
          const w = el.intro.getBoundingClientRect().width;
          const gap = parseFloat(getComputedStyle(el.layout).columnGap) || 0;
          el.scene.style.setProperty('--shift', `${Math.round((w + gap) / 2)}px`);
        }
        setPhase('ready');
        busy = false;
      } else if (jump === 'mid') {
        el.intro.classList.add('is-gone');
        el.leaf.style.opacity = '0';
        el.wipe.style.clipPath = 'inset(26.5% 21.5% 41.4% 62%)';
        setPhase('closing');
      }
    });
  }

  const onFirstGesture = () => {
    Sfx.boot();
    window.removeEventListener('pointerdown', onFirstGesture);
    window.removeEventListener('keydown', onFirstGesture);
  };
  window.addEventListener('pointerdown', onFirstGesture, { once: true });
  window.addEventListener('keydown', onFirstGesture, { once: true });

  document.addEventListener('visibilitychange', () => {
    if (!Sfx.ctx) return;
    if (document.hidden) Sfx.ctx.suspend();
    else Sfx.ctx.resume();
  });

  bootSequence();
  window.__moonchat = { Sfx, sky, conversations, selectConv, launch };
})();





