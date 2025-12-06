
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

function getFaqBase() {
  const s = localStorage.getItem('faqBase');
  if (s && s.trim()) return s.trim();
  return '/public/faq';
}

function isIOSHost() {
  try { return new URL(window.location.href).searchParams.get('ios') === '1'; } catch (_) { return false }
}

function setLang(lang) {
  try { localStorage.setItem('lang', lang); } catch(_){}
  const url = new URL(window.location.href);
  url.searchParams.set('lang', lang);
  window.location.replace(url.toString());
}

function t(obj, lang) { return lang === 'zh' ? obj.zh : obj.en; }

function renderHeader(navEl, title, lang, fallbackHref) {
  navEl.innerHTML = `<a href="#" class="back" id="back">←</a><span class="nav-label" id="backLabel"></span><h1>${title}</h1>`;
  const back = navEl.querySelector('#back');
  back.addEventListener('click', (e)=>{
    e.preventDefault();
    if (window.history.length > 1) { window.history.back(); return; }
    if (fallbackHref) { window.location.href = fallbackHref; return; }
    window.location.href = `index.html?lang=${detectLang()}`;
  });
}

function renderLangToggle(container, lang) {
  if (isIOSHost()) return;
  const div = document.createElement('div'); div.className = 'tab';
  div.innerHTML = `
    <a href="#" class="${lang==='zh'?'active':''}" data-lang="zh">中文</a>
    <a href="#" class="${lang==='en'?'active':''}" data-lang="en">English</a>
  `;
  div.querySelectorAll('a').forEach(a=>{ a.addEventListener('click', (e)=>{ e.preventDefault(); setLang(a.dataset.lang); }); });
  const before = container.querySelector('#cats');
  if (before) container.insertBefore(div, before); else container.prepend(div);
}

function renderSearch(container, lang) {
  const wrap = document.createElement('div');
  const input = document.createElement('input'); input.className = 'input';
  input.placeholder = lang==='zh' ? '按问题或疑问搜索' : 'Search by question or topic';
  wrap.appendChild(input);
  const hint = document.createElement('div'); hint.className = 'helper'; hint.style.display = 'none';
  hint.textContent = lang==='zh' ? '请输入至少 2 个字符进行搜索' : 'Enter at least 2 characters to search';
  wrap.appendChild(hint);
  const card = document.createElement('div'); card.className = 'card'; card.style.display = 'none'; card.style.marginTop = '8px';
  const ul = document.createElement('ul'); ul.className = 'list'; card.appendChild(ul); wrap.appendChild(card);
  const before = container.querySelector('#cats'); if (before) container.insertBefore(wrap, before); else container.appendChild(wrap);
  function update() {
    const q = input.value.trim();
    if (q.length < 2) { hint.style.display='block'; card.style.display='none'; return; }
    hint.style.display='none'; card.style.display='block'; ul.innerHTML='';
    const lang = detectLang();
    const results = HelpData.articles.filter(a=> (a.zh+a.en).toLowerCase().includes(q.toLowerCase()) ).slice(0, 20);
    results.forEach(a=>{ const li = document.createElement('li'); li.textContent=t(a, lang); li.addEventListener('click', ()=>{ window.location.href = `article.html?id=${encodeURIComponent(a.id)}&lang=${lang}${isIOSHost()? '&ios=1':''}`; }); ul.appendChild(li); });
  }
  input.addEventListener('input', update);
}
