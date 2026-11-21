(() => {
  const root = document.documentElement;
  const btn = document.getElementById('themeBtn');
  const store = {
    get() { try { return localStorage.getItem('mondchat-theme'); } catch { return null; } },
    set(v) { try { localStorage.setItem('mondchat-theme', v); } catch { /* file:// or private mode */ } },
  };
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

  const apply = (theme) => {
    root.dataset.theme = theme;
  };

  apply(store.get() || (prefersDark ? 'dark' : 'light'));

  btn?.addEventListener('click', () => {
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
    apply(next);
    store.set(next);
  });

  // Hero quote: a few of the login-screen lines, one at a time.
  const quotes = [
    ['我们只能看到前方很短的一段，但那里已经有足够多的事情要做。', '艾伦·图灵'],
    ['预测未来的最好方式，就是创造它。', '艾伦·凯'],
    ['最危险的一句话是：我们一直都是这么做的。', '格蕾丝·霍珀'],
    ['我无法创造的东西，我就无法理解。', '理查德·费曼'],
    ['计算机能否思考，这个问题并不比潜艇能否游泳更有趣。', '艾兹格·迪杰斯特拉'],
    ['真正的问题不是机器是否会思考，而是人是否会思考。', '斯金纳'],
  ];
  const figure = document.getElementById('heroQuote');
  const quoteText = figure?.querySelector('blockquote p');
  const quoteBy = figure?.querySelector('figcaption');
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let index = 0;
  let timer = 0;
  let paused = false;

  const swap = () => {
    if (paused || !figure || !quoteText || !quoteBy) return;
    index = (index + 1) % quotes.length;
    const [text, author] = quotes[index];
    if (reduced) {
      quoteText.textContent = text;
      quoteBy.textContent = author;
      return;
    }
    figure.classList.add('is-swapping');
    window.setTimeout(() => {
      quoteText.textContent = text;
      quoteBy.textContent = author;
      figure.classList.remove('is-swapping');
    }, 420);
  };

  const stop = () => {
    if (timer) window.clearInterval(timer);
    timer = 0;
  };
  const start = () => {
    stop();
    // 减少动态时不轮换，只留当前这一条。
    if (reduced) return;
    timer = window.setInterval(swap, 8000);
  };

  if (figure) {
    // 悬停、键盘聚焦都暂停；读屏用户把焦点放上去就不会被换内容。
    figure.addEventListener('mouseenter', () => { paused = true; });
    figure.addEventListener('mouseleave', () => { paused = false; });
    figure.addEventListener('focusin', () => { paused = true; });
    figure.addEventListener('focusout', () => { paused = false; });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stop();
      else start();
    });
    start();
  }

  // 安装包只跑在 x64 的 Windows 10+：点「现在体验」先提醒，确认了才去下载。
  const INSTALLER = 'https://github.com/flssr/moonchat/releases/download/preview/MondChat-Setup-1.0.0.exe';
  const gate = document.getElementById('getGate');
  const getBtn = document.getElementById('getBtn');

  getBtn?.addEventListener('click', (event) => {
    // 没有原生 dialog 就把链接让过去；没有 JS 时它本身就是下载链接。
    if (typeof gate?.showModal !== 'function') return;
    event.preventDefault();
    gate.showModal();
  });

  if (gate) {
    gate.addEventListener('click', (event) => {
      const target = event.target;
      if (target.closest('[data-confirm]')) {
        gate.close();
        window.location.href = INSTALLER;
      } else if (target.closest('[data-close]')) {
        gate.close();
      } else if (target === gate) {
        // 只有点面板外的遮罩才关，点面板里的留白不算。
        const box = gate.getBoundingClientRect();
        const outside = event.clientX < box.left || event.clientX > box.right
          || event.clientY < box.top || event.clientY > box.bottom;
        if (outside) gate.close();
      }
    });
  }
})();
