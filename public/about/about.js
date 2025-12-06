function detectLang() {
  try {
    const url = new URL(window.location.href);
    const qp = url.searchParams.get('lang');
    if (qp === 'zh' || qp === 'en') { try { localStorage.setItem('lang', qp); } catch(_){} return qp; }
    const stored = localStorage.getItem('lang');
    if (stored) return stored;
  } catch(_) {}
  const sys = (navigator.language || 'en').toLowerCase();
  return sys.startsWith('zh') ? 'zh' : 'en';
}

function isIOSHost() {
  try { return new URL(window.location.href).searchParams.get('ios') === '1'; } catch(_) { return false; }
}

function getLangFolder(lang) { return lang === 'zh' ? 'zh-Hans' : 'en'; }

function getAboutBase() { return '/public/about'; }

function renderLangToggle(container, lang, topic) {
  if (isIOSHost()) return;
  const div = document.createElement('div');
  div.className = 'tab';
  div.innerHTML = `
    <a href="#" class="${lang==='zh'?'active':''}" data-lang="zh">中文</a>
    <a href="#" class="${lang==='en'?'active':''}" data-lang="en">English</a>
  `;
  div.addEventListener('click', function(e){
    const t = e.target; if (t.tagName.toLowerCase() !== 'a') return;
    const next = t.getAttribute('data-lang'); if (!next) return;
    try { localStorage.setItem('lang', next); } catch(_){}
    const u = new URL(window.location.href);
    u.searchParams.set('lang', next);
    if (topic) u.searchParams.set('topic', topic);
    window.location.href = u.toString();
  });
  container.appendChild(div);
}

function pruneRedundantTitle(root, topic) {
  const norm = s => (s || '').replace(/\s+/g, '').toLowerCase();
  const target = norm(topic);
  let removed = 0;
  let i = 0;
  while (i < root.childNodes.length && removed < 2 && i < 6) {
    const n = root.childNodes[i];
    const text = norm(n.textContent || '');
    const isHeaderTag = (n.tagName || '').toLowerCase();
    const headerLike = ['h1','h2','h3','h4','p'].includes(isHeaderTag);
    if (headerLike && (text.includes(target) || target.includes(text))) {
      root.removeChild(n);
      removed++;
      continue;
    }
    i++;
  }
}

