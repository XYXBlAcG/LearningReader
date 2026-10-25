"use strict";
const readerStorage=ReaderCourseContext.storage(window.localStorage,window.READER_SOURCE_ID||'standalone',window.READER_LEGACY===true,window.READER_LEGACY_STATE||{});
const readerSessionStorage=ReaderCourseContext.storage(window.sessionStorage,window.READER_SOURCE_ID||'standalone');

const $ = (id) => document.getElementById(id);
const DATA_SOURCE = ReaderDataSource.createReaderDataSource(window.READER_DATA_MODE || "api");
const SIDEBAR_TREE = ReaderSidebarTree;
const PINNED_FILES = ReaderPinnedFiles;

let FILES = { notes: [], exercises: [] };
let SEARCH_SECTIONS = [];
let searchState = "loading";
let selectedSearchResult = -1;
let active = null;
let documentPaths = {note:{},exercise:{}};

let zoom = parseFloat(readerStorage.getItem("reader_zoom") || "1") || 1;
let sidebarOpen = !window.matchMedia("(max-width: 860px)").matches;
let immersive = readerStorage.getItem("reader_immersive") === "1";
let collapsed = JSON.parse(readerStorage.getItem("reader_collapsed") || "{}");
let pinnedFiles = PINNED_FILES.parsePinned(readerStorage.getItem("reader_pinned_files"));
let searchText = "";
const savedOutline = readerStorage.getItem("reader_outline");
let outlineOpen = savedOutline === null
  ? !window.matchMedia("(max-width: 1160px)").matches
  : savedOutline !== "0";
let rightPanel = readerStorage.getItem("reader_right_panel") || "outline";
let outlineWidth = parseFloat(readerStorage.getItem("reader_outline_width") || "420") || 420;
let restoreScrollTop = 0;
let scrollSaveTimer = 0;
let graphView = null;
const navigation = new ReaderNavigation(history, readerStorage, readerSessionStorage);
let navigationRequest = 0;
let navigationAbort = null;
let documentRenderQueue = Promise.resolve();
let documentRendering = false;
let hostBridge = null;
const READING_BLOCKS = '.prose h1,.prose h2,.prose h3,.prose h4,.prose p:not(.preview-status),.prose li,.prose pre';

function captureReadingPosition() {
  const article = $('article');
  const blocks = [...article.querySelectorAll(READING_BLOCKS)];
  const edge = article.getBoundingClientRect().top;
  const index = blocks.findIndex(block => block.getBoundingClientRect().bottom > edge);
  return { top: article.scrollTop, block: index,
    offset: index >= 0 ? blocks[index].getBoundingClientRect().top - edge : 0,
    references: [...article.querySelectorAll('.ref-toggle.open')].map(button => button.textContent.trim()) };
}

function updateNavigation() {
  $('backPage').disabled = !navigation.canBack;
  $('forwardPage').disabled = !navigation.canForward;
  const query = $('historySearch').value.trim().toLowerCase();
  const list = $('historyList');
  list.replaceChildren();
  for (const record of navigation.records) {
    const pool = record.kind === 'note' ? FILES.notes : FILES.exercises;
    const currentPath = documentPaths[record.kind]?.[record.path] || record.path;
    const file = pool.find(item => item.path === currentPath);
    const label = file ? sidebarLabel(file) : record.path.split('/').pop();
    if (!`${label} ${record.path}`.toLowerCase().includes(query)) continue;
    const button = document.createElement('button');
    button.className = 'history-item';
    const title = document.createElement('span');title.textContent = label;
    const detail = document.createElement('small');
    detail.textContent = `${record.kind === 'note' ? '笔记' : '练习'} · ${record.path.split('/')[0]} · ${new Date(record.time).toLocaleString('zh-CN')}${file ? '' : ' · 文件已不存在'}`;
    button.append(title, detail);
    button.onclick = () => {
      $('historyPanel').hidePopover();
      selectFile(record.kind, record.path, '', { snapshot: record.snapshot });
    };
    list.append(button);
  }
  if (!list.children.length) list.textContent = query ? '没有匹配的记录' : '暂无阅读记录';
  hostBridge?.publish();
}

let mathTypesetQueue = Promise.resolve();

function escHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

ReaderSelectionCopy.bind($('article'));

function typeset() {
  if (window.MathJax && MathJax.typesetPromise) {
    mathTypesetQueue = mathTypesetQueue
      .then(() => MathJax.typesetPromise([$("article"), $("outline")]))
      .catch((e) => console.warn("MathJax:", e));
    return mathTypesetQueue;
  }
  return Promise.resolve();
}

async function renderMarkdown(md, anchor = "", snapshot = null) {
  const linkedSource = ReaderKnowledgeGraph.renderWikiLinks(md);
  const isExercise = active && active.kind === "exercise";
  const html = ReaderMarkdown.render(linkedSource, source => isExercise ? ReaderExerciseCopy.formatSubquestions(source) : source);
  const proseClass = isExercise ? "prose exercise-prose" : "prose";
  ReaderProblemPreviews.dispose();
  $("article").innerHTML = '<div class="' + proseClass + '">' + html + "</div>";
  ReaderExerciseCopy.enhance($("article").firstElementChild, isExercise);
  ReaderCodeBlocks.enhance($("article"));
  enhanceLocalMedia($("article"));
  setupCollapsibleReferences($("article"));
  if (snapshot) for (const button of $('article').querySelectorAll('.ref-toggle')) {
    if (snapshot.references?.includes(button.textContent.trim())) {
      button.classList.add('open');button.nextElementSibling.classList.add('open');
    }
  }
  ReaderProblemPreviews.enhance($("article"));
  setupHeadings($("article"));
  await typeset();
  await new Promise((resolve) => requestAnimationFrame(() => {
    const target = anchor ? document.getElementById(anchor) : null;
    if (snapshot) {
      const blocks = [...$('article').querySelectorAll(READING_BLOCKS)];
      const block = blocks[snapshot.block];
      $('article').scrollTop = snapshot.top || 0;
      if (block) $('article').scrollTop += block.getBoundingClientRect().top - $('article').getBoundingClientRect().top - snapshot.offset;
    } else if (target) target.scrollIntoView({ behavior: "instant", block: "start" });
    else $("article").scrollTop = restoreScrollTop;
    updateReadingProgress();
    updateActiveHeading();
    ReaderProblemPreviews.activate();
    resolve();
  }));
}

/* ---------- 本地图片、视频与交互可视化 ---------- */
function encodeMediaPath(path) {
  return "/media/" + path.split("/").map(encodeURIComponent).join("/");
}

function localMediaPath(src) {
  if (!src || /^(?:https?:|data:|blob:|#)/i.test(src)) return null;
  let value;
  try { value = decodeURIComponent(src.split(/[?#]/)[0]); }
  catch { value = src.split(/[?#]/)[0]; }
  if (value.startsWith('/media/') || value.startsWith('/')) return null;
  return ReaderCourseContext.normalize((active?.path.split('/').slice(0,-1).join('/')||'')+'/'+value);
}

function interactiveEmbed(img, path) {
  const box = document.createElement("figure");
  box.className = "interactive-embed";
  const caption = document.createElement("figcaption");
  const label = img.alt || "交互可视化";
  const panel = document.createElement("dialog");
  panel.className = "interactive-panel";
  panel.setAttribute("open", "");
  panel.setAttribute("aria-label", label);
  caption.innerHTML = '<span>✦ ' + escHtml(label) + '</span><a target="_blank" rel="noopener">新窗口打开 ↗</a>';
  const suffix = img.getAttribute("src").match(/[?#].*$/)?.[0] || "";
  const url = encodeMediaPath(path) + suffix;
  const isProblemPreview = path.endsWith("/三维题目预览.html");
  const isGeometryPreview = isProblemPreview || /空间直线与平面|二次曲面与截痕/.test(path);
  if (isGeometryPreview) box.classList.add('geometry-preview');
  if (isProblemPreview) box.classList.add("problem-preview");
  caption.querySelector("a").href = url;
  const fullButton = document.createElement("button");
  fullButton.type = "button";
  fullButton.className = "embed-fullscreen";
  fullButton.textContent = "全屏";
  fullButton.setAttribute("aria-label", "全屏查看交互图");
  fullButton.addEventListener("click", () => {
    if (panel.matches(":modal")) panel.close();
    else {
      panel.close();
      panel.showModal();
      fullButton.textContent = "退出全屏";
      fullButton.setAttribute("aria-label", "退出交互图全屏");
    }
  });
  panel.addEventListener("close", () => {
    if (panel.open) return;
    panel.show();
    fullButton.textContent = "全屏";
    fullButton.setAttribute("aria-label", "全屏查看交互图");
  });
  caption.append(fullButton);
  const frame = document.createElement("iframe");
  if (isGeometryPreview) frame.dataset.previewSrc = url;
  else frame.src = url;
  frame.title = label;
  frame.loading = "lazy";
  frame.allowFullscreen = true;
  frame.setAttribute("sandbox", "allow-scripts allow-forms allow-pointer-lock allow-downloads");
  const viewport = document.createElement("div");
  viewport.className = "interactive-viewport";
  viewport.title = "拖动右下角调整图的显示高度";
  viewport.append(frame);
  panel.append(caption, viewport);
  box.append(panel);
  img.replaceWith(box);
}

function enhanceLocalMedia(root) {
  root.querySelectorAll("img[src]").forEach((img) => {
    const path = localMediaPath(img.getAttribute("src"));
    if (!path) return;
    if (/\.html?$/i.test(path)) interactiveEmbed(img, path);
    else img.src = encodeMediaPath(path);
  });
  root.querySelectorAll("video[src], audio[src], source[src], iframe[src]").forEach((el) => {
    const path = localMediaPath(el.getAttribute("src"));
    if (path) el.src = encodeMediaPath(path);
  });
}

/* ---------- 本页目录与阅读进度 ---------- */
function headingId(text, used) {
  const base = (text || "section").trim().toLowerCase()
    .replace(/\s+/g, "-").replace(/[^a-z0-9\u4e00-\u9fff-]/g, "") || "section";
  let id = base, n = 2;
  while (used.has(id)) id = base + "-" + n++;
  used.add(id);
  return id;
}

function setupHeadings(root) {
  const list = $("outlineList");
  list.innerHTML = "";
  const used = new Set();
  const headings = [...root.querySelectorAll(".prose h1, .prose h2, .prose h3, .prose h4")];
  headings.forEach((h) => {
    const content = h.cloneNode(true);
    content.querySelectorAll("button").forEach((button) => button.remove());
    h.id = headingId(content.textContent, used);
    const b = document.createElement("button");
    b.className = "outline-item level-" + h.tagName[1];
    b.innerHTML = content.innerHTML;
    b.dataset.target = h.id;
    b.onclick = () => selectFile(active.kind, active.path, h.id);
    list.appendChild(b);
  });
  list.classList.toggle("empty", headings.length < 2);
}

function updateReadingProgress() {
  const article = $("article");
  const max = article.scrollHeight - article.clientHeight;
  const value = max > 0 ? Math.min(1, article.scrollTop / max) : 1;
  $("readingProgress").firstElementChild.style.width = (value * 100).toFixed(1) + "%";
}

function updateActiveHeading() {
  const headings = [...$("article").querySelectorAll(".prose h1[id], .prose h2[id], .prose h3[id], .prose h4[id]")];
  let current = headings[0];
  for (const h of headings) {
    if (h.getBoundingClientRect().top <= 110) current = h;
    else break;
  }
  document.querySelectorAll(".outline-item").forEach((b) => {
    b.classList.toggle("active", !!current && b.dataset.target === current.id);
  });
}

function scrollKey(item = active) {
  return item ? "reader_scroll:" + item.kind + ":" + item.path : "";
}

function saveScroll() {
  if (active && !documentRendering) {
    readerStorage.setItem(scrollKey(), String($("article").scrollTop));
    if (navigation.current?.kind === active.kind && navigation.current?.path === active.path) navigation.checkpoint(captureReadingPosition());
  }
}

/* ---------- 侧栏：搜索 / 折叠 / 互跳 ---------- */
function highlight(s) {
  if (!searchText) return escHtml(s);
  const terms = searchText.trim().split(/\s+/).filter(Boolean)
    .map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  if (!terms.length) return escHtml(s);
  return escHtml(s).replace(new RegExp("(" + terms.join("|") + ")", "ig"), "<mark>$1</mark>");
}

function findCounterpart(kind,path) {
  const section=window.COURSE?.sections.find(item=>item.kind===kind);
  const otherKind=kind==='note'?'exercise':'note';
  const otherSection=window.COURSE?.sections.find(item=>item.kind===otherKind);
  if(!section||!otherSection)return null;
  const prefix=section.path==='.'?'':section.path+'/';
  if(!path.startsWith(prefix))return null;
  const target=(otherSection.path==='.'?'':otherSection.path+'/')+path.slice(prefix.length);
  return ReaderCourseContext.resolve(target,null,FILES);
}

function updateCounterpart() {
  const btn = $("counterpartBtn");
  if (!active) { btn.hidden = true; return; }
  const cp = findCounterpart(active.kind, active.path);
  if (!cp) { btn.hidden = true; return; }
  btn.hidden = false;
  btn.textContent = active.kind === "note" ? "⇄ 对应题目" : "⇄ 对应笔记";
  btn.onclick = () => selectFile(cp.kind, cp.path);
}

function activePool() {
  if (!active) return [];
  return active.kind === "note" ? FILES.notes : FILES.exercises;
}

function updateFileNavigation() {
  const pool = activePool();
  const index = active ? pool.findIndex((f) => f.path === active.path) : -1;
  $("prevFile").disabled = index <= 0;
  $("nextFile").disabled = index < 0 || index >= pool.length - 1;
  $("prevFile").title = index > 0 ? "上一篇：" + pool[index - 1].label + "（[）" : "已经是第一篇";
  $("nextFile").title = index >= 0 && index < pool.length - 1
    ? "下一篇：" + pool[index + 1].label + "（]）" : "已经是最后一篇";
}

function moveFile(delta) {
  const pool = activePool();
  const index = active ? pool.findIndex((f) => f.path === active.path) : -1;
  const next = pool[index + delta];
  if (next) selectFile(active.kind, next.path);
}

/* ---------- 参考答案自动收起（点击展开） ---------- */
function setupCollapsibleReferences(root) {
  const headings = [...root.querySelectorAll("h1, h2, h3, h4")];
  headings.forEach((h) => {
    if (!/^参考/.test((h.textContent || "").trim())) return;
    const level = +h.tagName[1];
    const body = document.createElement("div");
    body.className = "ref-body";
    let el = h.nextElementSibling;
    while (el && !(/^H[1-4]$/.test(el.tagName) && +el.tagName[1] <= level)) {
      const next = el.nextElementSibling;
      body.appendChild(el);
      el = next;
    }
    const btn = document.createElement("button");
    btn.className = "ref-toggle";
    btn.innerHTML = '<span class="caret">▶</span><span>' +
      escHtml((h.textContent || "").trim()) + "</span>";
    btn.onclick = () => {
      body.classList.toggle("open");
      btn.classList.toggle("open", body.classList.contains("open"));
      saveScroll();
    };
    h.replaceWith(btn);
    btn.after(body);
  });
}

async function selectFile(kind, path, anchor = "", options = {}) {
  clearTimeout(scrollSaveTimer);
  if (!options.traversal) saveScroll();
  const previousPath = path;
  path = documentPaths[kind]?.[path] || path;
  const request = ++navigationRequest;
  navigationAbort?.abort();
  navigationAbort = new AbortController();
  $('article').setAttribute('aria-busy', 'true');
  try {
    const pool = kind === 'note' ? FILES.notes : FILES.exercises;
    if (!pool.some(file => file.path === path)) throw new Error('文件已不存在：' + path);
    const r = await fetch(DATA_SOURCE.fileUrl(kind, path), { signal: navigationAbort.signal });
    if (!r.ok) throw new Error('无法读取文件（HTTP ' + r.status + '）：' + path);
    const markdown = await r.text();
    documentRenderQueue = documentRenderQueue.catch(() => {}).then(async () => {
      if (request !== navigationRequest) return;
      documentRendering = true;
      try {
        active = { kind, path, source: markdown };
        restoreScrollTop = Number(readerStorage.getItem(scrollKey()) || 0);
        document.querySelectorAll('.file-item').forEach(el => {
          el.classList.toggle('active', el.dataset.kind === kind && el.dataset.path === path);
          if (el.dataset.kind === kind && el.dataset.path === path) {
            for (let parent = el.parentElement; parent; parent = parent.parentElement) {
              if (parent.matches('details.chapter-folder')) parent.open = true;
            }
          }
        });
        $('crumb').textContent = (kind === 'note' ? '📒 ' : '✏️ ') + path;
        updateCounterpart();updatePinButton();updateFileNavigation();
        graphView.showDocument(kind, path);
        const initialPosition = options.snapshot || { top: anchor ? 0 : restoreScrollTop, references: [] };
        if (options.traversal) {
          navigation.current = { ...navigation.current, kind, path, snapshot: initialPosition };
          navigation.checkpoint(initialPosition);
        } else navigation.visit({ kind, path, anchor }, initialPosition);
        const entry = navigation.current;
        updateNavigation();
        await renderMarkdown(markdown, anchor, options.snapshot || null);
        if (navigation.current === entry) {
          navigation.checkpoint(captureReadingPosition());
          navigation.remember(navigation.current);
        }
        if (request !== navigationRequest) return;
        readerStorage.setItem('reader_last', JSON.stringify({kind:active.kind,path:active.path}));
        if (previousPath !== path) showNavigationError('文件已改名，当前打开：' + path);
        updateNavigation();
      } finally { documentRendering = false; }
    });
    await documentRenderQueue;
  } catch (e) {
    if (request !== navigationRequest || e.name === 'AbortError') return;
    if (options.traversal) {
      active = null;
      ReaderProblemPreviews.dispose();
      $('article').replaceChildren();
      $('outlineList').replaceChildren();
      $('crumb').textContent = path;
      graphView.showDocument(kind, path);
      document.querySelectorAll('.file-item.active').forEach(el => el.classList.remove('active'));
      updateCounterpart();updatePinButton();updateFileNavigation();
    }
    showNavigationError(String(e.message || e));
    updateNavigation();
  } finally {
    if (request === navigationRequest) $('article').removeAttribute('aria-busy');
  }
}

function showNavigationError(message) {
  $('navigationMessage')?.remove();
  const notice = document.createElement('div');
  notice.id = 'navigationMessage';notice.className = 'navigation-message';notice.setAttribute('role', 'status');
  const text = document.createElement('span');text.textContent = message;
  const close = document.createElement('button');close.type = 'button';close.className = 'text-btn';close.textContent = '关闭';close.onclick = () => notice.remove();
  notice.append(text, close);$('article').prepend(notice);
}

/* ---------- 侧栏 ---------- */
function sidebarSection(file) {
  const parts=file.path.split('/');
  return parts.length===1?{key:'entry',label:'入口'}:{key:parts[0],label:parts[0]};
}

function sidebarLabel(file) {
  return file.label || file.path;
}

function createFileItem(file, kind, depth = 0, pinned = false) {
  const b = document.createElement("button");
  b.className = "file-item" + (pinned ? " pinned-file-item" : "");
  b.innerHTML = (pinned ? '<span class="pin-marker">📌</span>' : "") +
    highlight(sidebarLabel(file));
  b.title = file.path;
  b.dataset.kind = kind;
  b.dataset.path = file.path;
  b.dataset.depth = String(depth);
  b.classList.toggle("active", !!active && active.kind === kind && active.path === file.path);
  b.onclick = () => selectFile(kind, file.path);
  return b;
}

function renderPinnedGroup() {
  const resolved = PINNED_FILES.resolvePinned(pinnedFiles, FILES);
  if (!resolved.length) return;
  const sec = document.createElement("div");
  sec.className = "group pinned-group";
  const head = document.createElement("div");
  head.className = "group-title";
  head.innerHTML = '<span class="pin-marker">📌</span><span>置顶</span><span class="count">' +
    resolved.length + "</span>";
  sec.appendChild(head);
  const list = document.createElement("div");
  list.className = "file-list pinned-files";
  resolved.forEach(({ kind, file }) => list.appendChild(createFileItem(file, kind, 0, true)));
  sec.appendChild(list);
  $("groups").appendChild(sec);
}

function renderGroup(title, items, kind) {
  const q = searchText.trim().toLowerCase();
  const filtered = q
    ? items.filter((f) => f.label.toLowerCase().includes(q) || f.path.toLowerCase().includes(q))
    : items;
  const sec = document.createElement("div");
  sec.className = "group";
  sec.dataset.expansionKey = kind;
  const isCollapsed = !q && !!collapsed[kind];
  sec.classList.toggle("collapsed", isCollapsed);

  const head = document.createElement("button");
  head.className = "group-title";
  head.innerHTML = '<span class="caret">▾</span><span>' + escHtml(title) + "</span>" +
    '<span class="count">' + (q ? filtered.length + "/" + items.length : items.length) + "</span>";
  head.onclick = () => {
    if (q) return;
    collapsed[kind] = !collapsed[kind];
    readerStorage.setItem("reader_collapsed", JSON.stringify(collapsed));
    sec.classList.toggle("collapsed", collapsed[kind]);
  };
  sec.appendChild(head);

  const list = document.createElement("div");
  list.className = "file-list";
  const sections = new Map();
  filtered.forEach((file) => {
    const meta = sidebarSection(file);
    if (!sections.has(meta.key)) sections.set(meta.key, { ...meta, files: [] });
    sections.get(meta.key).files.push(file);
  });
  sections.forEach((subgroup) => {
    const wrap = document.createElement("div");
    wrap.className = "subgroup";
    const stateKey = kind + ":" + subgroup.key;
    wrap.dataset.expansionKey = stateKey;
    const subgroupCollapsed = !q && !!collapsed[stateKey];
    wrap.classList.toggle("collapsed", subgroupCollapsed);
    const subhead = document.createElement("button");
    subhead.className = "subgroup-title";
    subhead.innerHTML = '<span class="caret">▾</span><span>' + escHtml(subgroup.label) +
      '</span><span class="count">' + subgroup.files.length + "</span>";
    subhead.onclick = () => {
      if (q) return;
      collapsed[stateKey] = !collapsed[stateKey];
      readerStorage.setItem("reader_collapsed", JSON.stringify(collapsed));
      wrap.classList.toggle("collapsed", collapsed[stateKey]);
    };
    wrap.appendChild(subhead);
    const files = document.createElement("div");
    files.className = "subgroup-files";
    const renderNodes = (nodes, target) => {
      nodes.forEach((node) => {
        if (!node.file) {
          const folder = document.createElement('details');
          folder.className = 'chapter-folder';
          const folderKey = kind + ':folder:' + node.path;
          folder.dataset.expansionKey = folderKey;
          folder.open = !!q || SIDEBAR_TREE.folderIsOpen(collapsed, folderKey, node.path, active?.path);
          folder.addEventListener('toggle', () => {
            if (searchText.trim()) return;
            collapsed[folderKey] = !folder.open;
            readerStorage.setItem('reader_collapsed', JSON.stringify(collapsed));
          });
          const summary = document.createElement('summary');
          summary.textContent = node.label;
          folder.append(summary);
          renderNodes(node.children, folder);
          target.append(folder);
          return;
        }
        target.appendChild(createFileItem(node.file, kind, node.depth));
        renderNodes(node.children, target);
      });
    };
    renderNodes(SIDEBAR_TREE.buildFolderTree(subgroup.files), files);
    wrap.appendChild(files);
    list.appendChild(wrap);
  });
  sec.appendChild(list);
  $("groups").appendChild(sec);
}

function setSidebarExpanded(expanded) {
  const nodes = [...$('groups').querySelectorAll('[data-expansion-key]')];
  SIDEBAR_TREE.setExpansion(collapsed, nodes.map(node => node.dataset.expansionKey), expanded);
  for (const node of nodes) {
    if (node.tagName === 'DETAILS') node.open = expanded;
    else node.classList.toggle('collapsed', !expanded);
  }
  readerStorage.setItem('reader_collapsed', JSON.stringify(collapsed));
}

$('expandAll').onclick = () => setSidebarExpanded(true);
$('collapseAll').onclick = () => setSidebarExpanded(false);

function setSelectedSearchResult(index) {
  const results = [...document.querySelectorAll(".search-result")];
  if (!results.length) {
    selectedSearchResult = -1;
    return;
  }
  selectedSearchResult = (index + results.length) % results.length;
  results.forEach((item, position) => {
    const selected = position === selectedSearchResult;
    item.classList.toggle("selected", selected);
    item.setAttribute("aria-selected", selected ? "true" : "false");
  });
  results[selectedSearchResult].scrollIntoView({ block: "nearest" });
}

function clearSearch() {
  $("searchInput").value = "";
  searchText = "";
  selectedSearchResult = -1;
  buildSidebar();
}

function renderSearchResults() {
  const root = $("groups");
  const status = document.createElement("div");
  status.className = "search-status";
  if (searchState === "loading") {
    status.textContent = "正在建立全文索引…";
    root.appendChild(status);
    return;
  }
  if (searchState === "error") {
    status.textContent = "全文索引暂时不可用，正在匹配文件名";
    root.appendChild(status);
    renderGroup(window.COURSE?.sections.find(s=>s.kind==='note')?.title||"课程", FILES.notes, "note");
    if(FILES.exercises.length)renderGroup(window.COURSE?.sections.find(s=>s.kind==='exercise')?.title||"练习", FILES.exercises, "exercise");
    return;
  }
  const results = ReaderSearch.searchSections(SEARCH_SECTIONS, searchText);
  status.textContent = results.length ? "找到 " + results.length + " 个相关位置" : "没有找到相关概念";
  root.appendChild(status);
  const list = document.createElement("div");
  list.className = "search-results";
  list.setAttribute("role", "listbox");
  results.forEach((result, index) => {
    const button = document.createElement("button");
    button.className = "search-result";
    button.setAttribute("role", "option");
    button.setAttribute("aria-selected", "false");
    button.dataset.index = String(index);
    button.innerHTML = '<span class="search-result-kind">' +
      (result.kind === "note" ? "笔记" : "题目") + '</span><span class="search-result-location">' +
      highlight(result.documentLabel) + " › " + highlight(result.heading) +
      '</span><span class="search-result-snippet">' + highlight(result.snippet) + "</span>";
    button.onclick = () => {
      const target = { kind: result.kind, path: result.path, anchor: result.anchor || "" };
      clearSearch();
      selectFile(target.kind, target.path, target.anchor);
    };
    button.onmouseenter = () => setSelectedSearchResult(index);
    list.appendChild(button);
  });
  root.appendChild(list);
}

function buildSidebar() {
  $("groups").innerHTML = "";
  if (searchText.trim()) {
    renderSearchResults();
    return;
  }
  renderPinnedGroup();
  renderGroup(window.COURSE?.sections.find(s=>s.kind==='note')?.title||"课程", FILES.notes, "note");
  if(FILES.exercises.length)renderGroup(window.COURSE?.sections.find(s=>s.kind==='exercise')?.title||"练习", FILES.exercises, "exercise");
}

function updatePinButton() {
  const button = $("pinFileBtn");
  button.disabled = !active;
  const pinned = !!active && pinnedFiles.includes(PINNED_FILES.documentKey(active.kind, active.path));
  button.classList.toggle("active", pinned);
  button.setAttribute("aria-pressed", pinned ? "true" : "false");
  button.setAttribute("aria-label", pinned ? "取消置顶当前课程" : "置顶当前课程");
  button.title = (pinned ? "取消置顶当前课程" : "置顶当前课程") + "（Shift+P）";
  hostBridge?.publish();
}

function toggleActivePin() {
  if (!active) return;
  pinnedFiles = PINNED_FILES.togglePinned(
    pinnedFiles,
    PINNED_FILES.documentKey(active.kind, active.path),
  );
  readerStorage.setItem("reader_pinned_files", JSON.stringify(pinnedFiles));
  updatePinButton();
  buildSidebar();
}

function applySidebar() {
  document.body.classList.toggle("sidebar-open", sidebarOpen);
  document.body.classList.toggle("sidebar-closed", !sidebarOpen);
  $("mask").classList.toggle("show", sidebarOpen && window.matchMedia("(max-width: 860px)").matches);
  hostBridge?.publish();
}

function toggleSidebar() {
  sidebarOpen = !sidebarOpen;
  applySidebar();
}

/* ---------- 缩放 / 主题 / 样式 / 沉浸 ---------- */
function setZoom(v) {
  zoom = Math.min(1.6, Math.max(0.7, v));
  document.documentElement.style.setProperty("--fs", (17 * zoom).toFixed(1) + "px");
  $("zoomVal").textContent = Math.round(zoom * 100) + "%";
  readerStorage.setItem("reader_zoom", String(zoom));
  hostBridge?.publish();
}

function toggleShortcuts() {
  const settings = $('settingsPanel');
  if (!settings.matches(':popover-open')) settings.showPopover();
  $('shortcutsPanel').open = !$('shortcutsPanel').open;
}

function closeShortcuts() {
  if ($('settingsPanel').matches(':popover-open')) $('settingsPanel').hidePopover();
}

function setImmersive(on) {
  immersive = on;
  document.body.classList.toggle("immersive", on);
  $("exitImmersive").classList.toggle("show", on);
  readerStorage.setItem("reader_immersive", on ? "1" : "0");
  hostBridge?.publish();
}

function setOutline(on) {
  outlineOpen = on;
  document.body.classList.toggle("outline-closed", !on);
  $("outlineToggle").classList.toggle("active", on);
  readerStorage.setItem("reader_outline", on ? "1" : "0");
  hostBridge?.publish();
  if (on && rightPanel === "graph" && graphView) {
    requestAnimationFrame(() => graphView.resize());
  }
}

function clampOutlineWidth(value) {
  return Math.min(720, Math.max(280, Math.min(value, window.innerWidth - 480)));
}

function setOutlineWidth(value, persist = false) {
  outlineWidth = clampOutlineWidth(value);
  document.documentElement.style.setProperty("--outline-width", outlineWidth + "px");
  $("outlineResize").setAttribute("aria-valuenow", String(Math.round(outlineWidth)));
  if (persist) readerStorage.setItem("reader_outline_width", String(Math.round(outlineWidth)));
  if (graphView && rightPanel === "graph") requestAnimationFrame(() => graphView.resize());
}

function setRightPanel(panel) {
  rightPanel = panel === "graph" ? "graph" : "outline";
  const graphActive = rightPanel === "graph";
  $("outlineTab").classList.toggle("active", !graphActive);
  $("graphTab").classList.toggle("active", graphActive);
  $("outlineTab").setAttribute("aria-selected", graphActive ? "false" : "true");
  $("graphTab").setAttribute("aria-selected", graphActive ? "true" : "false");
  $("outlinePanel").hidden = graphActive;
  $("graphPanel").hidden = !graphActive;
  readerStorage.setItem("reader_right_panel", rightPanel);
  hostBridge?.publish();
  if (graphActive) requestAnimationFrame(() => graphView.resize());
}

/* ---------- 内部 .md 链接跳转 ---------- */


$("article").addEventListener("click", (e) => {
  const a = e.target.closest("a[href]");
  if (!a) return;
  const directAnchor = a.getAttribute('href') || '';
  if (directAnchor.startsWith('#') && active) {
    e.preventDefault();
    selectFile(active.kind, active.path, directAnchor.slice(1) ? decodeURIComponent(directAnchor.slice(1)) : '',
      directAnchor === '#' ? { snapshot: { top: 0, references: [] } } : {});
    return;
  }
  let href;
  try {
    href = decodeURIComponent(a.getAttribute("href") || "");
  } catch {
    href = a.getAttribute("href") || "";
  }
  if (!/\.md(#.*)?$/i.test(href) || /^https?:|^#/.test(href)) return;
  e.preventDefault();
  const hrefParts = href.split("#");
  const raw = hrefParts[0].replace(/^\.\//, "");
  const anchor = hrefParts.length > 1 ? headingId(hrefParts.slice(1).join("#"), new Set()) : "";
  const destination=ReaderCourseContext.resolve(raw,active,FILES);
  if(destination)selectFile(destination.kind,destination.path,anchor);
  else showNavigationError("此文件不在课程阅读范围内，请检查课程清单或原仓库链接。");
});

/* ---------- 事件绑定 ---------- */
$("sidebarToggle").onclick = toggleSidebar;
$("sidebarClose").onclick = toggleSidebar;
$("mask").onclick = toggleSidebar;
$("searchInput").addEventListener("input", (e) => {
  searchText = e.target.value.trim();
  selectedSearchResult = -1;
  buildSidebar();
  if (active) {
    document.querySelectorAll(".file-item").forEach((el) => {
      el.classList.toggle("active",
        el.dataset.kind === active.kind && el.dataset.path === active.path);
    });
  }
});
$("zoomIn").onclick = () => setZoom(zoom + 0.05);
$("zoomOut").onclick = () => setZoom(zoom - 0.05);
$("prevFile").onclick = () => moveFile(-1);
$("nextFile").onclick = () => moveFile(1);
$('backPage').onclick = () => { saveScroll(); if (navigation.canBack) history.back(); };
$('forwardPage').onclick = () => { saveScroll(); if (navigation.canForward) history.forward(); };
$('historyPanel').addEventListener('beforetoggle', event => { if (event.newState === 'open') updateNavigation(); });
$('historySearch').addEventListener('input', updateNavigation);
$('clearHistory').onclick = () => {
  navigation.clear();updateNavigation();
};
window.addEventListener('popstate', event => {
  clearTimeout(scrollSaveTimer);
  const entry = navigation.adopt(event.state);
  if (entry) {
    active = null;
    selectFile(entry.kind, entry.path, '', { traversal: true, snapshot: entry.snapshot });
  }
  updateNavigation();
});
$("pinFileBtn").onclick = toggleActivePin;
const previewMedia = window.matchMedia('(max-width: 760px)');
function updatePreviewPreference() {
  const enabled = ReaderPreviewPreference.previewEnabled(readerStorage.getItem('reader_preview_enabled'), previewMedia.matches);
  ReaderProblemPreviews.setEnabled(enabled);
  $('previewToggle').setAttribute('aria-pressed', String(enabled));
  $('previewToggle').textContent = enabled ? '三维：开' : '三维：关';
  hostBridge?.publish();
}
function togglePreview() {
  readerStorage.setItem('reader_preview_enabled', String($('previewToggle').getAttribute('aria-pressed') !== 'true'));
  updatePreviewPreference();
}
$('previewToggle').onclick = togglePreview;
previewMedia.addEventListener('change', updatePreviewPreference);
updatePreviewPreference();
$("outlineToggle").onclick = () => setOutline(!outlineOpen);
$("outlineTab").onclick = () => setRightPanel("outline");
$("graphTab").onclick = () => setRightPanel("graph");
$("immersiveToggle").onclick = () => {
  setImmersive(!immersive);
  closeShortcuts();
};
$("exitImmersive").onclick = () => setImmersive(false);


document.addEventListener("wheel", (e) => {
  if (!(e.ctrlKey || e.metaKey)) return;
  if (e.target.closest("#graphCanvas")) return;
  e.preventDefault();
  setZoom(zoom + (e.deltaY < 0 ? 0.05 : -0.05));
}, { passive: false });

$("graphCanvas").addEventListener("wheel", (e) => {
  if (!(e.ctrlKey || e.metaKey)) return;
  e.preventDefault();
  e.stopPropagation();
}, { passive: false });

$("outlineResize").addEventListener("pointerdown", (e) => {
  if (window.matchMedia("(max-width: 1160px)").matches) return;
  const startX = e.clientX;
  const startWidth = outlineWidth;
  const handle = e.currentTarget;
  handle.setPointerCapture(e.pointerId);
  document.body.classList.add("resizing-outline");

  handle.onpointermove = (moveEvent) => {
    setOutlineWidth(startWidth + startX - moveEvent.clientX);
  };
  handle.onpointerup = () => {
    handle.onpointermove = null;
    handle.onpointerup = null;
    handle.onpointercancel = null;
    document.body.classList.remove("resizing-outline");
    readerStorage.setItem("reader_outline_width", String(Math.round(outlineWidth)));
  };
  handle.onpointercancel = handle.onpointerup;
});

$("outlineResize").addEventListener("keydown", (e) => {
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return;
  e.preventDefault();
  if (e.key === "Home") setOutlineWidth(280, true);
  else if (e.key === "End") setOutlineWidth(720, true);
  else setOutlineWidth(outlineWidth + (e.key === "ArrowLeft" ? 20 : -20), true);
});

document.addEventListener("keydown", (e) => {
  const typing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) ||
    document.activeElement.isContentEditable;
  if (e.key === "Escape") {
    closeShortcuts();
    if (immersive) setImmersive(false);
  }
  if (e.key === "Escape" && document.activeElement === $("searchInput")) {
    clearSearch();
    $("searchInput").blur();
  }
  if (document.activeElement === $("searchInput") && e.key === "ArrowDown") {
    e.preventDefault();
    setSelectedSearchResult(selectedSearchResult + 1);
    return;
  }
  if (document.activeElement === $("searchInput") && e.key === "ArrowUp") {
    e.preventDefault();
    setSelectedSearchResult(selectedSearchResult - 1);
    return;
  }
  if (document.activeElement === $("searchInput") && e.key === "Enter") {
    const results = [...document.querySelectorAll(".search-result")];
    const target = results[selectedSearchResult >= 0 ? selectedSearchResult : 0];
    if (target) {
      e.preventDefault();
      target.click();
    }
    return;
  }
  if (!typing && (e.altKey || e.metaKey) && e.key === "ArrowLeft") {
    e.preventDefault();
    $('backPage').click();
  }
  if (!typing && (e.altKey || e.metaKey) && e.key === "ArrowRight") {
    e.preventDefault();
    $('forwardPage').click();
  }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === "/") {
    e.preventDefault();
    if (!sidebarOpen) toggleSidebar();
    $("searchInput").focus();
  }
  if (e.key === "?") { e.preventDefault(); toggleShortcuts(); }
  if (e.key === "[") { e.preventDefault(); moveFile(-1); }
  if (e.key === "]") { e.preventDefault(); moveFile(1); }
  if (e.key.toLowerCase() === "j") $("article").scrollBy({ top: 150, behavior: "smooth" });
  if (e.key.toLowerCase() === "k") $("article").scrollBy({ top: -150, behavior: "smooth" });
  if (e.key.toLowerCase() === "b") toggleSidebar();
  if (e.key.toLowerCase() === "t") setOutline(!outlineOpen);
  if (e.key.toLowerCase() === "g") {
    if (!outlineOpen) setOutline(true);
    setRightPanel("graph");
  }
  if (e.shiftKey && e.key.toLowerCase() === "p") {
    e.preventDefault();
    toggleActivePin();
    return;
  }
  if (e.key.toLowerCase() === "p" && !$("counterpartBtn").hidden) $("counterpartBtn").click();
  if (e.key.toLowerCase() === "f") setImmersive(!immersive);
});

window.addEventListener("resize", () => {
  applySidebar();
  if (!window.matchMedia("(max-width: 1160px)").matches) setOutlineWidth(outlineWidth);
});
$("article").addEventListener("scroll", () => {
  updateReadingProgress();
  updateActiveHeading();
  clearTimeout(scrollSaveTimer);
  scrollSaveTimer = setTimeout(saveScroll, 180);
});
window.addEventListener("beforeunload", saveScroll);

/* ---------- 初始化 ---------- */
setZoom(zoom);
setOutlineWidth(outlineWidth);
setImmersive(immersive);
setOutline(outlineOpen);
graphView = ReaderKnowledgeGraph.createView({
  container: $("graphCanvas"),
  empty: $("graphEmpty"),
  incoming: $("graphIncoming"),
  outgoing: $("graphOutgoing"),
  mode: $("graphMode"),
  onNavigate: (node) => selectFile(node.kind, node.path, node.anchor || ""),
  onRendered: () => typeset(),
});
setRightPanel(rightPanel);
applySidebar();

hostBridge = ReaderHostBridge.install({
  identity: () => ReaderExplanation.identity(active, $('article')),
  material: () => ReaderExplanation.course(active, $('article'), $('crumb').textContent),
  read: () => ({
    title: active ? sidebarLabel((activePool().find(file => file.path === active.path)) || { label: active.path }) : (window.COURSE?.title||'知序'),
    path: active?.path || '', hasDocument: !!active,
    canBack: navigation.canBack, canForward: navigation.canForward,
    pinned: !!active && pinnedFiles.includes(PINNED_FILES.documentKey(active.kind, active.path)),
    counterpart: active && findCounterpart(active.kind, active.path) ? (active.kind === 'note' ? '对应题目' : '对应笔记') : '',
    sidebar: sidebarOpen, outline: outlineOpen, panel: rightPanel, immersive, zoom,
    previews: $('previewToggle').getAttribute('aria-pressed') === 'true',
    history: navigation.records.map(record => {
      const path = documentPaths[record.kind]?.[record.path] || record.path;
      const pool = record.kind === 'note' ? FILES.notes : FILES.exercises;
      const file = pool.find(item => item.path === path);
      return { kind: record.kind, path: record.path, time: record.time,
        label: file ? sidebarLabel(file) : record.path.split('/').pop(), missing: !file };
    }),
  }),
  dispatch: (command, payload) => {
    switch (command) {
      case 'back': saveScroll(); if (navigation.canBack) history.back(); break;
      case 'forward': saveScroll(); if (navigation.canForward) history.forward(); break;
      case 'sidebar': toggleSidebar(); break;
      case 'pin': toggleActivePin(); break;
      case 'counterpart': {
        const target = active && findCounterpart(active.kind, active.path);
        if (target) selectFile(target.kind, target.path);
        break;
      }
      case 'outline': setOutline(!outlineOpen); break;
      case 'graph': setOutline(true); setRightPanel(rightPanel === 'graph' ? 'outline' : 'graph'); break;
      case 'immersive': setImmersive(!immersive); break;
      case 'previews': togglePreview(); break;
      case 'zoomIn': setZoom(zoom + .05); break;
      case 'zoomOut': setZoom(zoom - .05); break;
      case 'previous': moveFile(-1); break;
      case 'next': moveFile(1); break;
      case 'clearHistory': navigation.clear(); updateNavigation(); break;
      case 'openHistory': {
        const record = navigation.records.find(item => item.kind === payload?.kind && item.path === payload?.path);
        if (record) selectFile(record.kind, record.path, '', { snapshot: record.snapshot });
        break;
      }
    }
  },
});

fetch(DATA_SOURCE.graphUrl())
  .then((response) => {
    if (!response.ok) throw new Error("HTTP " + response.status);
    return response.json();
  })
  .then((graph) => graphView.setData(graph))
  .catch((error) => {
    $("graphEmpty").hidden = false;
    $("graphEmpty").textContent = "知识图谱加载失败：" + String(error);
  });

fetch(DATA_SOURCE.searchUrl())
  .then((response) => {
    if (!response.ok) throw new Error("HTTP " + response.status);
    return response.json();
  })
  .then((index) => {
    SEARCH_SECTIONS = index.sections || [];
    searchState = "ready";
    if (searchText) buildSidebar();
  })
  .catch(() => {
    searchState = "error";
    if (searchText) buildSidebar();
  });

Promise.all([fetch(DATA_SOURCE.filesUrl()).then(r=>r.json()), fetch('/reader/document-paths.json').then(r=>r.json())])
  .then(([data, paths]) => {
    documentPaths = paths;
    pinnedFiles = [...new Set(pinnedFiles.map(key => {
      const separator = key.indexOf(':');
      const kind = key.slice(0,separator);
      const old = key.slice(separator+1);
      return kind + ':' + (paths[kind]?.[old] || old);
    }))];
    readerStorage.setItem('reader_pinned_files', JSON.stringify(pinnedFiles));
    for (const [kind, entries] of Object.entries(paths)) {
      for (const [old, current] of Object.entries(entries)) {
        const previous = 'reader_scroll:' + kind + ':' + old;
        const next = 'reader_scroll:' + kind + ':' + current;
        if (readerStorage.getItem(previous) !== null && readerStorage.getItem(next) === null) {
          readerStorage.setItem(next, readerStorage.getItem(previous));
          readerStorage.removeItem(previous);
        }
      }
    }
    FILES = data;
    document.title=window.COURSE?.title||'知序';
    const appName=document.querySelector('.app-name');if(appName)appName.textContent=document.title;
    buildSidebar();
    const query = new URLSearchParams(location.search);
    const requested = query.get("kind") && query.get("path")
      ? { kind: query.get("kind"), path: query.get("path"), anchor: query.get("anchor") || "" } : null;
    const last = requested || JSON.parse(readerStorage.getItem("reader_last") || "null");
    if (last) last.path = paths[last.kind]?.[last.path] || last.path;
    const pool = last && last.kind === "note" ? FILES.notes : FILES.exercises;
    if (last && pool.some((f) => f.path === last.path)) {
      const snapshot = navigation.current?.kind === last.kind && navigation.current?.path === last.path
        ? navigation.current.snapshot : null;
      selectFile(last.kind, last.path, last.anchor || "", { snapshot });
    } else {
      const entry=ReaderCourseContext.resolve(window.COURSE?.entry||'',null,FILES);
      const first=entry||(FILES.notes[0]?{kind:'note',path:FILES.notes[0].path}:FILES.exercises[0]?{kind:'exercise',path:FILES.exercises[0].path}:null);
      if(first)selectFile(first.kind,first.path);
    }
  })
  .catch((err) => {
    $("article").innerHTML = '<div class="prose"><p class="err">加载文件列表失败：' +
      escHtml(String(err)) + "</p></div>";
  });
