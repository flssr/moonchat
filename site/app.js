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

  // Hero quote: 交流、相遇与人机共生，不选纯计算机科学的句子。
  const quotes = [
    ['我们只能看到前方很短的一段，但那里已经有足够多的事情要做。', '艾伦·图灵'],
    ['语言是误解的根源。', '圣埃克苏佩里'],
    ['我的语言的界限，意味着我的世界的界限。', '维特根斯坦'],
    ['语言是存在之家。', '海德格尔'],
    ['我们最好确信，交给机器的目的，正是我们真正想要的目的。', '诺伯特·维纳'],
    ['有朋自远方来，不亦乐乎。', '孔子'],
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

  // 标题和引言里的 <br> 换成行遮罩：每行各自从自己的遮罩里推上来，
  // 滚走再滑回来还会重演；没有 JS 时这里不拆，标题按整块淡入。
  document.querySelectorAll('.hero h1, .reveal h2, .band blockquote p').forEach((el) => {
    if (!/<br\s*\/?>/i.test(el.innerHTML)) return;
    el.innerHTML = el.innerHTML
      .split(/<br\s*\/?>/i)
      .map((line, i) => `<span class="ln"><span class="ln__i" style="--i:${i}">${line.trim()}</span></span>`)
      .join('');
  });
})();
