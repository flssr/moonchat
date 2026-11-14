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
    btn?.setAttribute('aria-pressed', String(theme === 'dark'));
    btn?.setAttribute('aria-label', theme === 'dark' ? '切换到日间主题' : '切换到夜间主题');
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
    timer = window.setInterval(swap, 8000);
  };

  if (figure) {
    figure.addEventListener('mouseenter', () => { paused = true; });
    figure.addEventListener('mouseleave', () => { paused = false; });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stop();
      else start();
    });
    start();
  }

  const items = document.querySelectorAll('.reveal');
  if (!items.length) return;
  if (!('IntersectionObserver' in window)) {
    items.forEach((el) => el.classList.add('is-in'));
    return;
  }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      io.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.06 });

  items.forEach((el) => io.observe(el));
})();
