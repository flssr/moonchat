/* 首屏的星空与流星：只用 ink 色的低透明度点与细线，动效放慢，减少动态时只留一张静止星图。 */
(() => {
  const stage = document.querySelector('.hero-wrap');
  const canvas = document.querySelector('.sky');
  const moon = document.querySelector('.moon');
  if (!stage || !canvas) return;

  const ctx = canvas.getContext('2d');
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  let width = 0;
  let height = 0;
  let stars = [];
  let meteor = null;
  let nextMeteorAt = 0;
  let frame = 0;
  let last = 0;
  let visible = true;

  const rand = (min, max) => min + Math.random() * (max - min);

  function ink(alpha) {
    const dark = document.documentElement.dataset.theme === 'dark';
    const r = dark ? 237 : 26;
    const g = dark ? 233 : 25;
    const b = dark ? 225 : 23;
    return `rgba(${r},${g},${b},${alpha})`;
  }

  function buildStars() {
    // 稀疏就够了：平均每 16000 平方像素一颗。
    const count = Math.max(14, Math.round((width * height) / 16000));
    stars = Array.from({ length: count }, () => ({
      x: Math.random() * width,
      y: Math.random() * height,
      r: rand(0.5, 1.15),
      phase: rand(0, Math.PI * 2),
      speed: rand(0.25, 0.9),
      drift: rand(-0.5, 0.5),
    }));
  }

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = stage.clientWidth;
    height = stage.clientHeight;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    buildStars();
  }

  function spawnMeteor(now) {
    const angle = rand(0.34, 0.5); // 与水平线的夹角：往下、往左
    const speed = rand(620, 960);
    meteor = {
      x: rand(width * 0.42, width * 1.04),
      y: rand(-12, height * 0.4),
      vx: -Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      length: rand(110, 190),
      age: 0,
      life: rand(780, 1200),
      alpha: rand(0.42, 0.58),
    };
    nextMeteorAt = now + rand(9000, 18000);
  }

  function drawMeteor() {
    const len = Math.hypot(meteor.vx, meteor.vy) || 1;
    const tailX = meteor.x - (meteor.vx / len) * meteor.length;
    const tailY = meteor.y - (meteor.vy / len) * meteor.length;
    const fade = Math.sin(Math.PI * (meteor.age / meteor.life));
    const alpha = meteor.alpha * fade;

    const gradient = ctx.createLinearGradient(tailX, tailY, meteor.x, meteor.y);
    gradient.addColorStop(0, ink(0));
    gradient.addColorStop(0.8, ink(alpha * 0.45));
    gradient.addColorStop(1, ink(alpha));

    ctx.strokeStyle = gradient;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(tailX, tailY);
    ctx.lineTo(meteor.x, meteor.y);
    ctx.stroke();

    ctx.fillStyle = ink(Math.min(alpha * 1.25, 0.4));
    ctx.beginPath();
    ctx.arc(meteor.x, meteor.y, 1.1, 0, Math.PI * 2);
    ctx.fill();
  }

  function loop(now) {
    frame = 0;
    if (document.hidden || !visible) return;

    const dt = Math.min(now - last, 50);
    last = now;
    const still = reduceMotion.matches;
    const parallax = Math.min(window.scrollY || 0, height) * 0.04;

    ctx.clearRect(0, 0, width, height);

    for (const star of stars) {
      const twinkle = 0.085 + 0.05 * Math.sin((now / 1000) * star.speed + star.phase);
      ctx.fillStyle = ink(still ? 0.1 : twinkle);
      ctx.beginPath();
      ctx.arc(star.x, star.y - parallax, star.r, 0, Math.PI * 2);
      ctx.fill();

      if (!still) {
        star.x += (star.drift * dt) / 1000;
        if (star.x < -2) star.x = width + 2;
        if (star.x > width + 2) star.x = -2;
      }
    }

    if (!still) {
      if (!meteor && now > nextMeteorAt) spawnMeteor(now);
      if (meteor) {
        meteor.age += dt;
        if (meteor.age >= meteor.life) {
          meteor = null;
        } else {
          meteor.x += (meteor.vx * dt) / 1000;
          meteor.y += (meteor.vy * dt) / 1000;
          drawMeteor();
        }
      }
      frame = requestAnimationFrame(loop);
    }
  }

  function start() {
    if (frame) return;
    if (document.hidden || !visible) return;
    last = performance.now();
    if (!meteor && performance.now() > nextMeteorAt) nextMeteorAt = last + rand(3000, 7000);
    frame = requestAnimationFrame(loop);
  }

  function stop() {
    if (frame) {
      cancelAnimationFrame(frame);
      frame = 0;
    }
  }

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible) start();
    else stop();
  }, { threshold: 0 }).observe(stage);

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stop();
    else start();
  });

  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      stop();
      resize();
      start();
    }, 120);
  });

  // 月亮随页面轻微下沉：只给滚动一点纵深，不做视差特效。
  let scrollFrame = 0;
  function updateMoon() {
    scrollFrame = 0;
    if (!moon || reduceMotion.matches) return;
    const offset = Math.min(window.scrollY || 0, height) * 0.06;
    moon.style.transform = `translate3d(0, ${offset}px, 0)`;
  }

  window.addEventListener('scroll', () => {
    if (!scrollFrame) scrollFrame = requestAnimationFrame(updateMoon);
  }, { passive: true });

  reduceMotion.addEventListener('change', () => {
    stop();
    if (reduceMotion.matches && moon) moon.style.transform = '';
    else updateMoon();
    start();
  });

  updateMoon();
  resize();
  start();
})();
