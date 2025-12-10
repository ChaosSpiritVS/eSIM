
const SupportedLocales = ['en','zh-Hans','zh-Hant','ja','ko','th','id','es','pt','ms','vi','ar'];
const LocaleDisplayNames = {
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'th': 'ไทย',
  'id': 'Bahasa Indonesia',
  'es': 'Español',
  'pt': 'Português',
  'ms': 'Bahasa Melayu',
  'vi': 'Tiếng Việt',
  'ar': 'العربية'
};

const UIStrings = {
  help_center: {
    'zh-Hans': '帮助中心', 'zh-Hant': '幫助中心', 'en': 'Help Center', 'ja': 'ヘルプセンター', 'ko': '도움말 센터', 'th': 'ศูนย์ช่วยเหลือ', 'id': 'Pusat Bantuan', 'es': 'Centro de ayuda', 'pt': 'Central de Ajuda', 'ms': 'Pusat Bantuan', 'vi': 'Trung tâm trợ giúp', 'ar': 'مركز المساعدة'
  },
  back_all: {
    'zh-Hans': '查看所有类别', 'zh-Hant': '檢視所有類別', 'en': 'See all categories', 'ja': 'すべてのカテゴリを表示', 'ko': '모든 카테고리 보기', 'th': 'ดูหมวดหมู่ทั้งหมด', 'id': 'Lihat semua kategori', 'es': 'Ver todas las categorías', 'pt': 'Ver todas as categorias', 'ms': 'Lihat semua kategori', 'vi': 'Xem tất cả danh mục', 'ar': 'عرض جميع الفئات'
  },
  back_cat: {
    'zh-Hans': '返回该分类', 'zh-Hant': '返回該類別', 'en': 'Back to category', 'ja': 'カテゴリに戻る', 'ko': '카테고리로 돌아가기', 'th': 'กลับไปที่หมวดหมู่', 'id': 'Kembali ke kategori', 'es': 'Volver a la categoría', 'pt': 'Voltar à categoria', 'ms': 'Kembali ke kategori', 'vi': 'Quay lại danh mục', 'ar': 'الرجوع إلى الفئة'
  },
  search_placeholder: {
    'zh-Hans': '按问题或疑问搜索', 'zh-Hant': '依問題或疑問搜尋', 'en': 'Search by question or topic', 'ja': '質問やトピックで検索', 'ko': '질문 또는 주제별 검색', 'th': 'ค้นหาตามคำถามหรือหัวข้อ', 'id': 'Cari berdasarkan pertanyaan atau topik', 'es': 'Buscar por pregunta o tema', 'pt': 'Pesquisar por pergunta ou tópico', 'ms': 'Cari mengikut soalan atau topik', 'vi': 'Tìm theo câu hỏi hoặc chủ đề', 'ar': 'ابحث حسب السؤال أو الموضوع'
  },
  search_hint: {
    'zh-Hans': '请输入至少 2 个字符进行搜索', 'zh-Hant': '請輸入至少 2 個字元以搜尋', 'en': 'Enter at least 2 characters to search', 'ja': '検索には2文字以上入力してください', 'ko': '검색하려면 최소 2자를 입력하세요', 'th': 'ป้อนอย่างน้อย 2 อักขระเพื่อค้นหา', 'id': 'Masukkan setidaknya 2 karakter untuk mencari', 'es': 'Introduce al menos 2 caracteres para buscar', 'pt': 'Insira pelo menos 2 caracteres para pesquisar', 'ms': 'Masukkan sekurang-kurangnya 2 aksara untuk mencari', 'vi': 'Nhập ít nhất 2 ký tự để tìm kiếm', 'ar': 'أدخل 2 أحرف على الأقل للبحث'
  },
  doc_unable: {
    'zh-Hans': '无法读取文档，点击下载查看：', 'zh-Hant': '無法讀取文件，點擊下載查看：', 'en': 'Unable to read document. Download: ', 'ja': 'ドキュメントを読み込めません。ダウンロード：', 'ko': '문서를 읽을 수 없습니다. 다운로드: ', 'th': 'ไม่สามารถอ่านเอกสารได้ ดาวน์โหลด: ', 'id': 'Tidak dapat membaca dokumen. Unduh: ', 'es': 'No se puede leer el documento. Descargar: ', 'pt': 'Não foi possível ler o documento. Baixar: ', 'ms': 'Tidak dapat membaca dokumen. Muat turun: ', 'vi': 'Không thể đọc tài liệu. Tải xuống: ', 'ar': 'تعذر قراءة المستند. تنزيل: '
  }
};

const CategoryNames = {
  'about': {
    'zh-Hans': '关于 eSIM', 'zh-Hant': '關於 eSIM', 'en': 'About eSIM', 'ja': 'eSIM について', 'ko': 'eSIM 소개', 'th': 'เกี่ยวกับ eSIM', 'id': 'Tentang eSIM', 'es': 'Acerca de eSIM', 'pt': 'Sobre eSIM', 'ms': 'Tentang eSIM', 'vi': 'Giới thiệu eSIM', 'ar': 'حول eSIM'
  },
  'getting-started': {
    'zh-Hans': 'eSIM 使用入门', 'zh-Hant': 'eSIM 使用入門', 'en': 'Getting Started', 'ja': 'はじめに', 'ko': '시작하기', 'th': 'เริ่มต้นใช้งาน', 'id': 'Mulai', 'es': 'Primeros pasos', 'pt': 'Primeiros passos', 'ms': 'Mula', 'vi': 'Bắt đầu', 'ar': 'البدء'
  },
  'manage': {
    'zh-Hans': '使用和管理 eSIM', 'zh-Hant': '使用與管理 eSIM', 'en': 'Using & Managing eSIM', 'ja': 'eSIM の使用と管理', 'ko': 'eSIM 사용 및 관리', 'th': 'การใช้งานและจัดการ eSIM', 'id': 'Menggunakan & Mengelola eSIM', 'es': 'Uso y gestión de eSIM', 'pt': 'Usar e gerenciar eSIM', 'ms': 'Menggunakan & Mengurus eSIM', 'vi': 'Sử dụng và quản lý eSIM', 'ar': 'استخدام وإدارة eSIM'
  },
  'account': {
    'zh-Hans': '我的帐户', 'zh-Hant': '我的帳戶', 'en': 'My Account', 'ja': 'マイアカウント', 'ko': '내 계정', 'th': 'บัญชีของฉัน', 'id': 'Akun saya', 'es': 'Mi cuenta', 'pt': 'Minha conta', 'ms': 'Akaun saya', 'vi': 'Tài khoản của tôi', 'ar': 'حسابي'
  },
  'troubleshoot': {
    'zh-Hans': '故障排除', 'zh-Hant': '疑難排解', 'en': 'Troubleshooting', 'ja': 'トラブルシューティング', 'ko': '문제 해결', 'th': 'การแก้ไขปัญหา', 'id': 'Pemecahan masalah', 'es': 'Solución de problemas', 'pt': 'Solução de problemas', 'ms': 'Penyelesaian masalah', 'vi': 'Khắc phục sự cố', 'ar': 'استكشاف الأخطاء وإصلاحها'
  }
};

function locStr(key, locale) { const m = UIStrings[key] || {}; return m[locale] || m['en']; }
function categoryTitle(objOrId, locale) { const id = typeof objOrId === 'string' ? objOrId : objOrId.id; const m = CategoryNames[id] || {}; return m[locale] || m['en'] || (typeof objOrId === 'object' ? t(objOrId, detectLang()) : id); }
function articleTitle(a, locale) { return locale.startsWith('zh') ? a.zh : a.en; }

const CatCnMap = { 'about': '关于 eSIM', 'getting-started': 'eSIM 使用入门', 'manage': '使用和管理 eSIM', 'account': '我的帐户', 'troubleshoot': '故障排除' };
const KnownCategoryCnToId = { '关于 eSIM': 'about', 'eSIM 使用入门': 'getting-started', '使用和管理 eSIM': 'manage', '我的帐户': 'account', '故障排除': 'troubleshoot' };
function computeArticlePath(a, locale) {
  const base = getFaqBase();
  const categoryCn = (a.catCn || CatCnMap[a.cat] || '').trim();
  const fileName = (a.file || '').split('/').pop();
  if (!fileName || !categoryCn) return a.file;
  const p = `${base}/${categoryCn}/${locale}/${fileName}`;
  return p;
}
function cacheKey(id, locale) { return `article-title:${locale}:${id}`; }
function getCachedArticleTitle(id, locale) { try { return localStorage.getItem(cacheKey(id, locale)) || ''; } catch(_) { return ''; } }
function setCachedArticleTitle(id, locale, title) { try { localStorage.setItem(cacheKey(id, locale), title); } catch(_){} }
function parseTitleFromHtml(html) {
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const el = doc.querySelector('h1, h2, h3, p, li');
    const t = (el && el.textContent ? el.textContent : '').trim();
    return t || '';
  } catch(_) { return ''; }
}
function fetchArticleTitle(a, locale) {
  const p = encodeURI(computeArticlePath(a, locale));
  const u = p + (p.includes('?') ? '&' : '?') + 'v=' + Date.now();
  return fetch(u, { cache: 'no-store' }).then(r=>{ if(!r.ok) throw new Error('HTTP '+r.status); return r.arrayBuffer(); })
    .then(buffer=> mammoth.convertToHtml({arrayBuffer: buffer}))
    .then(res=> parseTitleFromHtml(res.value || ''));
}
function localizedArticleTitle(a, locale, fallback) {
  const cached = getCachedArticleTitle(a.id, locale);
  if (cached) return Promise.resolve(cached);
  return fetchArticleTitle(a, locale).then(ti=>{ const val = ti && ti.trim() ? ti.trim() : fallback; if (val) setCachedArticleTitle(a.id, locale, val); return val; }).catch(()=> fallback);
}
function hydrateArticleTitle(el, a, locale, fallback) { localizedArticleTitle(a, locale, fallback).then(tt=>{ if (tt) el.textContent = tt; }); }

const DirCache = {};
function listDir(path) {
  const key = `dir:${path}`;
  if (DirCache[key]) return Promise.resolve(DirCache[key]);
  return fetch(encodeURI(path)).then(r=>r.text()).then(html=>{
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const anchors = Array.from(doc.querySelectorAll('a'));
    const entries = anchors.map(a=>{
      const href = a.getAttribute('href') || '';
      const name = (a.textContent || href || '').trim();
      const isDir = href.endsWith('/') || name.endsWith('/');
      const clean = decodeURIComponent(href.replace(/\/?$/, '')) || name.replace(/\/?$/, '');
      return { name: clean, href, isDir };
    }).filter(e=> e.name && e.name !== '.' && e.name !== '..');
    DirCache[key] = entries;
    return entries;
  });
}

function listCategories() {
  const base = getFaqBase();
  return listDir(`${base}/`).then(entries=> entries.filter(e=> e.isDir && !SupportedLocales.includes(e.name)).map(e=> e.name));
}

function listArticles(catCn, locale) {
  const base = getFaqBase();
  const p = `${base}/${catCn}/${locale}/`;
  return listDir(p).then(entries=> entries.filter(e=> !e.isDir && e.name.toLowerCase().endsWith('.docx')).map(e=> e.name));
}

function localizedCategoryDisplayName(catCn, locale) {
  const id = KnownCategoryCnToId[catCn];
  if (!id) return catCn;
  const m = CategoryNames[id] || {};
  return m[locale] || m['en'] || catCn;
}

let AllArticlesCache = {};
function getAllArticles(locale) {
  const key = `all:${locale}`;
  if (AllArticlesCache[key]) return Promise.resolve(AllArticlesCache[key]);
  return listCategories().then(cats=> Promise.all(cats.map(cn=> listArticles(cn, locale).then(files=> files.map(f=>({ catCn: cn, file: f, id: f })) )))).then(arrs=>{
    const flat = arrs.flat();
    AllArticlesCache[key] = flat;
    return flat;
  });
}

function normalizeLocale(sys) {
  const s = (sys || 'en').toLowerCase();
  if (s.startsWith('zh')) {
    if (s.includes('hant') || s.includes('tw') || s.includes('hk')) return 'zh-Hant';
    return 'zh-Hans';
  }
  if (s.startsWith('en')) return 'en';
  if (s.startsWith('ja')) return 'ja';
  if (s.startsWith('ko')) return 'ko';
  if (s.startsWith('th')) return 'th';
  if (s.startsWith('id')) return 'id';
  if (s.startsWith('es')) return 'es';
  if (s.startsWith('pt')) return 'pt';
  if (s.startsWith('ms') || s.startsWith('ml')) return 'ms';
  if (s.startsWith('vi')) return 'vi';
  if (s.startsWith('ar')) return 'ar';
  return 'en';
}

function detectLocale() {
  try {
    const stored = localStorage.getItem('locale');
    if (stored) return normalizeLocale(stored);
    const url = new URL(window.location.href);
    const qpLocale = url.searchParams.get('locale');
    const qpLang = url.searchParams.get('lang');
    const raw = (qpLocale || qpLang || '').trim();
    const norm = raw ? normalizeLocale(raw) : '';
    if (norm) { try { localStorage.setItem('locale', norm); } catch(_){} return norm; }
  } catch(_) {}
  return normalizeLocale(navigator.language || 'en');
}

function detectLang() {
  try {
    const stored = localStorage.getItem('lang');
    if (stored) return stored;
    const url = new URL(window.location.href);
    const qp = url.searchParams.get('lang');
    if (qp === 'zh' || qp === 'en') { try { localStorage.setItem('lang', qp); } catch(_){} return qp; }
  } catch(_) {}
  const loc = detectLocale();
  return loc.startsWith('zh') ? 'zh' : 'en';
}

function syncUrlWithStoredLocale() {
  try {
    const url = new URL(window.location.href);
    const storedLocale = normalizeLocale(localStorage.getItem('locale') || '');
    const storedLang = localStorage.getItem('lang') || (storedLocale.startsWith('zh') ? 'zh' : (storedLocale ? 'en' : ''));
    let changed = false;
    if (storedLocale && url.searchParams.get('locale') !== storedLocale) { url.searchParams.set('locale', storedLocale); changed = true; }
    if (storedLang && url.searchParams.get('lang') !== storedLang) { url.searchParams.set('lang', storedLang); changed = true; }
    if (changed) { window.location.replace(url.toString()); }
  } catch(_) {}
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
  try { localStorage.setItem('lang', lang); } catch(_){ }
  const url = new URL(window.location.href);
  url.searchParams.set('lang', lang);
  const locale = lang === 'zh' ? 'zh-Hans' : 'en';
  try { localStorage.setItem('locale', locale); } catch(_){}
  url.searchParams.set('locale', locale);
  window.location.replace(url.toString());
}

function t(obj, lang) { return lang === 'zh' ? obj.zh : obj.en; }

function renderHeader(navEl, title, lang, fallbackHref) {
  navEl.innerHTML = `<a href="#" class="back" id="back">←</a><span class="nav-label" id="backLabel"></span><h1>${title}</h1>`;
  const back = navEl.querySelector('#back');
  back.addEventListener('click', (e)=>{
    e.preventDefault();
    if (fallbackHref) { window.location.href = fallbackHref; return; }
    window.location.href = `index.html?lang=${detectLang()}&locale=${detectLocale()}`;
  });
}

function renderLangToggle(container, lang) {
  if (isIOSHost()) return;
  const locale = detectLocale();
  const wrap = document.createElement('div'); wrap.className = 'lang-row';
  const label = document.createElement('span'); label.className = 'lang-label'; label.textContent = 'Language / 语言';
  const sel = document.createElement('select'); sel.className = 'lang-select';
  SupportedLocales.forEach(loc=>{ const opt = document.createElement('option'); opt.value = loc; opt.textContent = LocaleDisplayNames[loc] || loc; sel.appendChild(opt); });
  sel.value = locale;
  sel.addEventListener('change', ()=>{
    const nextLocale = sel.value;
    const nextLang = nextLocale.startsWith('zh') ? 'zh' : 'en';
    try { localStorage.setItem('locale', nextLocale); localStorage.setItem('lang', nextLang); } catch(_) {}
    const url = new URL(window.location.href);
    url.searchParams.set('locale', nextLocale);
    url.searchParams.set('lang', nextLang);
    window.location.replace(url.toString());
  });
  wrap.appendChild(label); wrap.appendChild(sel);
  const before = container.querySelector('#cats'); if (before) container.insertBefore(wrap, before); else container.prepend(wrap);
}

function renderSearch(container, lang) {
  const wrap = document.createElement('div');
  const input = document.createElement('input'); input.className = 'input';
  const locale = detectLocale();
  input.placeholder = locStr('search_placeholder', locale);
  wrap.appendChild(input);
  const hint = document.createElement('div'); hint.className = 'helper'; hint.style.display = 'none';
  hint.textContent = locStr('search_hint', locale);
  wrap.appendChild(hint);
  const card = document.createElement('div'); card.className = 'card'; card.style.display = 'none'; card.style.marginTop = '8px';
  const ul = document.createElement('ul'); ul.className = 'list'; card.appendChild(ul); wrap.appendChild(card);
  const before = container.querySelector('#cats'); if (before) container.insertBefore(wrap, before); else container.appendChild(wrap);
  function update() {
    const q = input.value.trim();
    if (q.length < 2) { hint.style.display='block'; card.style.display='none'; return; }
    hint.style.display='none'; card.style.display='block'; ul.innerHTML='';
    const lang2 = detectLang(); const locale2 = detectLocale();
    getAllArticles(locale2).then(items=>{
      const out = [];
      for (let i=0;i<items.length && out.length<20;i++){
        const it = items[i];
        const key = cacheKey(it.id, locale2);
        const cached = getCachedArticleTitle(it.id, locale2);
        if ((cached && cached.toLowerCase().includes(q.toLowerCase())) || it.file.toLowerCase().includes(q.toLowerCase())) {
          out.push(it);
        }
      }
      if (out.length < 20) {
        const promises = items.slice(0, 50).map(it=> localizedArticleTitle({catCn: it.catCn, file: it.file, id: it.id}, locale2, it.file.replace(/\.docx$/i,''))
          .then(tt=> ({it, tt})));
        Promise.allSettled(promises).then(results=>{
          results.forEach(r=>{
            if (r.status==='fulfilled') {
              const {it, tt} = r.value; if (tt.toLowerCase().includes(q.toLowerCase())) out.push(it);
            }
          });
          ul.innerHTML='';
          out.slice(0,20).forEach(it=>{
            const li = document.createElement('li');
            const initial = getCachedArticleTitle(it.id, locale2) || it.file.replace(/\.docx$/i,'');
            li.textContent = initial;
            hydrateArticleTitle(li, {catCn: it.catCn, file: it.file, id: it.id}, locale2, initial);
            li.addEventListener('click', ()=>{ window.location.href = `article.html?cat=${encodeURIComponent(it.catCn)}&file=${encodeURIComponent(it.file)}&lang=${lang2}&locale=${locale2}${isIOSHost()? '&ios=1':''}`; });
            ul.appendChild(li);
          });
        });
      } else {
        ul.innerHTML='';
        out.slice(0,20).forEach(it=>{
          const li = document.createElement('li');
          const initial = getCachedArticleTitle(it.id, locale2) || it.file.replace(/\.docx$/i,'');
          li.textContent = initial;
          hydrateArticleTitle(li, {catCn: it.catCn, file: it.file, id: it.id}, locale2, initial);
          li.addEventListener('click', ()=>{ window.location.href = `article.html?cat=${encodeURIComponent(it.catCn)}&file=${encodeURIComponent(it.file)}&lang=${lang2}&locale=${locale2}${isIOSHost()? '&ios=1':''}`; });
          ul.appendChild(li);
        });
      }
    });
  }
  input.addEventListener('input', update);
}
