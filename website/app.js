(() => {
'use strict';
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const sleep = ms => new Promise(r => setTimeout(r, reduceMotion ? 0 : ms));
const cssVar = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

/* 顶栏滚动后出现分隔线 */
const nav = $('.nav');
const onScroll = () => nav.classList.toggle('scrolled', scrollY > 8);
addEventListener('scroll', onScroll, { passive: true });
onScroll();

/* 外观：默认跟随系统，手动选过就记在本机 */
let palette = readPalette();
function readPalette() { return { accent: cssVar('--accent'), attn: cssVar('--attn'), t3: cssVar('--t3') }; }
const systemDark = matchMedia('(prefers-color-scheme: dark)');
function paintThemeButtons() {
  const theme = document.documentElement.dataset.theme || (systemDark.matches ? 'dark' : 'light');
  $$('[data-theme-set]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.themeSet === theme)));
  palette = readPalette();
}
$$('[data-theme-set]').forEach(b => b.addEventListener('click', () => {
  document.documentElement.dataset.theme = b.dataset.themeSet;
  try { localStorage.setItem('cove-theme', b.dataset.themeSet); } catch (e) {}
  paintThemeButtons();
}));
systemDark.addEventListener('change', paintThemeButtons);
paintThemeButtons();

/* 下载：有正式版本就直链到压缩包并显示版本号，否则留在 Releases 页 */
fetch('https://api.github.com/repos/huyanxius/Cove/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
  .then(r => (r.ok ? r.json() : Promise.reject(r.status)))
  .then(release => {
    // 优先给 .dmg，没有再退到 .zip；dSYM 之类的调试包不算。
    const assets = (release.assets || []).filter(a => !/dsym/i.test(a.name));
    const pick = ext => assets.find(a => a.name.toLowerCase().endsWith(ext));
    const file = pick('.dmg') || pick('.zip');
    if (file) $$('[data-download]').forEach(a => { a.href = file.browser_download_url; });
    if (release.tag_name) {
      const preview = /preview/i.test(release.name || '') || release.prerelease;
      $$('[data-version]').forEach(s => { s.textContent = `${release.tag_name}${preview ? ' 公开预览' : ''} · `; });
    }
  })
  .catch(() => {});

/* ───────── 小螃蟹：逐格移植自 Sources/Cove/Views/PetView.swift 的 PixelCrab ─────────
   18×5 的格子，格子竖长（高 = 宽 × 1.7）；动作全是时间 t 的连续函数。 */
const SHELL = '#D97757', EYE = '#2A2925', ASPECT = 1.7;
const noise = n => { const x = Math.sin(n * 12.9898) * 43758.5453; return x - Math.floor(x); };
function pose(mood, t) {
  const p = { lift: 0, squash: 0, tilt: 0, shiftX: 0, lx: 0, ly: 0, shut: false, leg: 0, la: 0, ra: 0 };
  const slot = Math.floor(t / 3.2);
  const blinking = t - slot * 3.2 < 0.13 && noise(slot) > 0.25;
  if (mood === 'idle') {
    p.squash = 0.04 * Math.sin(t * 2.6);
    p.lx = [-1, 0, 1, 0][Math.floor(noise(Math.floor(t / 2.2)) * 4) % 4];
    p.shut = blinking;
    const walk = t % 8;
    if (walk < 1.6) {
      p.shiftX = Math.sin(walk / 1.6 * Math.PI) * 3;
      p.leg = Math.floor(t * 10) % 2;
      p.lift = Math.abs(Math.sin(t * 20)) * 0.25;
    }
  } else if (mood === 'working') {
    const hop = Math.abs(Math.sin(t * 6.5));
    p.lift = hop * 1.4;
    p.squash = hop < 0.25 ? 0.12 * (1 - hop / 0.25) : -0.06 * hop;
    p.leg = Math.floor(t * 12) % 2;
    p.la = Math.max(0, Math.sin(t * 13));
    p.ra = Math.max(0, -Math.sin(t * 13));
    p.lx = 1;
    p.shut = blinking;
  } else if (mood === 'thinking') {
    p.tilt = Math.sin(t * 1.8) * 5;
    p.squash = 0.03 * Math.sin(t * 1.8);
    p.lx = Math.sin(t * 0.9) > 0 ? 1 : -1;
    p.ly = -1;
    p.shut = blinking;
  } else if (mood === 'waving') {
    const hop = Math.max(0, Math.sin(t * 5));
    p.lift = hop * 1.2;
    p.squash = hop < 0.1 ? 0.1 : -0.04;
    p.la = 2 + Math.sin(t * 14) * 0.8;
    p.shut = blinking;
  } else if (mood === 'sleeping') {
    p.squash = 0.07 + 0.05 * Math.sin(t * 1.4);
    p.shut = true;
  }
  return p;
}
function drawCrab(ctx, W, H, mood, t) {
  ctx.clearRect(0, 0, W, H);
  const p = pose(mood, t);
  const w = Math.min(W / 24, H / (9 * ASPECT)), h = w * ASPECT;
  const groundY = H - h * 0.6, cx = W / 2 + p.shiftX * w;
  const shadowW = w * (13 - p.lift * 2.5);
  ctx.globalAlpha = Math.max(0, 0.1 - p.lift * 0.02);
  ctx.fillStyle = '#000';
  ctx.beginPath();
  ctx.ellipse(cx, groundY - h * 0.15 + h * 0.175, shadowW / 2, h * 0.175, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;

  ctx.save();
  ctx.translate(cx, groundY - h - p.lift * h);
  ctx.rotate(p.tilt * Math.PI / 180);
  ctx.scale(1 + p.squash * 0.6, 1 - p.squash);
  // 以身体底边中点为原点：列 0…17，行从上往下，第 4 行是腿。相邻的格子合成一块画，放大后不露缝。
  const block = (col, row, cols, rows, color) => { ctx.fillStyle = color; ctx.fillRect((col - 9) * w, (row - 4) * h, cols * w + 0.3, rows * h + 0.3); };
  const cell = (col, row, color) => block(col, row, 1, 1, color);
  (p.leg === 0 ? [4, 6, 11, 13] : [5, 7, 10, 12]).forEach(col => block(col, 3.5, 1, 1.5, SHELL));
  block(3, 0, 12, 4, SHELL);
  block(1, 2 - p.la, 2, 1, SHELL);
  block(15, 2 - p.ra, 2, 1, SHELL);
  for (const col of [5, 12]) {
    if (p.shut) { ctx.fillStyle = EYE; ctx.fillRect((col - 9 + p.lx * 0.5) * w, (1 - 4) * h + h * 0.55, w, h * 0.18); }
    else cell(col + p.lx * 0.5, 1 + p.ly * 0.4, EYE);
  }
  ctx.restore();

  const hx = cx, hy = groundY - h * 5 - p.lift * h;
  const dot = (x, y, color, alpha, size) => {
    ctx.globalAlpha = Math.max(0, alpha); ctx.fillStyle = color;
    ctx.fillRect(hx + x * w, hy + y * h * 0.6, w * size, w * size);
    ctx.globalAlpha = 1;
  };
  if (mood === 'working') {
    for (let i = 0; i < 3; i++) {
      const ph = (t * 1.6 + i / 3) % 1;
      dot(4 + i * 2 + Math.sin(ph * 6 + i) * 0.6, -ph * 3, palette.accent, 1 - ph, 0.8);
    }
  } else if (mood === 'thinking') {
    for (let i = 0; i < 3; i++) dot(5 + i * 2, -1 - i * 0.4, palette.accent, (Math.floor(t * 3) % 4) > i ? 1 : 0.25, 0.9);
  } else if (mood === 'waving') {
    const b = Math.abs(Math.sin(t * 5)) * 0.8;
    ctx.fillStyle = palette.attn;
    ctx.fillRect(hx + 8 * w, hy - (1.4 + b) * h, w * 0.9, h * 1.1);
    ctx.fillRect(hx + 8 * w, hy - b * h, w * 0.9, w * 0.9);
  } else if (mood === 'sleeping') {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = palette.t3;
    for (let i = 0; i < 2; i++) {
      const ph = (t * 0.35 + i / 2) % 1;
      ctx.globalAlpha = 1 - ph;
      ctx.font = `700 ${(7 + ph * 5) * w / 3.67}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
      ctx.fillText('z', hx + (5 + ph * 4) * w, hy - ph * h * 2.5);
    }
    ctx.globalAlpha = 1;
  }
}

const crabs = [];
function makeCrab(canvas, mood) {
  const crab = { canvas, mood, visible: true, ctx: canvas.getContext('2d') };
  crab.resize = () => {
    const r = canvas.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2);
    crab.W = r.width; crab.H = r.height;
    canvas.width = Math.round(r.width * dpr); canvas.height = Math.round(r.height * dpr);
    crab.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    crab.draw(1000);
  };
  crab.draw = t => { if (crab.W) drawCrab(crab.ctx, crab.W, crab.H, crab.mood, t); };
  crab.set = mood => { crab.mood = mood; if (reduceMotion) crab.draw(1000.6); };
  new IntersectionObserver(([e]) => { crab.visible = e.isIntersecting; }).observe(canvas);
  crabs.push(crab);
  crab.resize();
  return crab;
}
addEventListener('resize', () => crabs.forEach(c => c.resize()));
if (!reduceMotion) {
  const tick = now => {
    const t = now / 1000 + 1000;
    crabs.forEach(c => { if (c.visible && c.W) c.draw(t); });
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/* ───────── 演示窗口 ───────── */
const MOOD = { working: 'working', thinking: 'thinking', waiting: 'waving', idle: 'idle', ended: 'sleeping' };
const MOOD_TEXT = { working: '干活中', thinking: '想一想……', waving: '等你回复', idle: '待命', sleeping: '打盹' };
const EMPTY_TASKS = 'Claude 规划多步工作时，任务会列在这里。';
const EMPTY_FILES = 'Claude 在这个会话里改过的文件会出现在这里。';

const sessions = [
  {
    project: 'weekend-project', title: '给侧栏收个尾', agent: 'Claude Code', when: '刚刚', state: 'idle',
    msgs: [], tasks: [], files: [], diff: [], branch: 'refine-sidebar', changes: '',
    stats: ['—', '—', '—'],
  },
  {
    project: 'weekend-project', title: '设置页改成中文', agent: 'Codex', when: '2 分钟前', state: 'waiting', unread: true,
    approval: '运行 swift build',
    msgs: [
      { u: '设置页里的英文标签都换成中文，术语和侧栏保持一致。' },
      { a: '改了 SettingsView 里的 14 处文案：Archive 统一成「归档」，Pin 统一成「置顶」。我编译一下，确认没有问题。' },
      { tool: '编辑', path: 'SettingsView.swift', add: 14, del: 14 },
    ],
    tasks: [{ t: '替换设置页文案', s: 'done' }, { t: '编译检查', s: 'doing' }],
    files: [{ n: 'SettingsView.swift', a: 14, d: 14 }],
    diff: [['del', '−  Toggle("Pin to top", …'], ['add', '+  Toggle("置顶", …'], ['del', '−  Button("Archive")'], ['add', '+  Button("归档")']],
    branch: 'zh-settings', changes: '1 处改动',
    stats: ['52s', '8.9k ↓  1.2k ↑', '$0.04'],
  },
  {
    project: 'weekend-project', title: '读一读启动流程', agent: 'Claude Code', when: '20 分钟前', state: 'idle',
    msgs: [
      { u: 'App 启动的时候都做了些什么？按顺序讲讲。' },
      { tool: '读取', path: 'App/Launch.swift' },
      { a: '一共三步：先读本地配置，再恢复上次打开的窗口，最后在后台检查更新。检查更新失败不会挡住启动，只会记一条日志。' },
    ],
    tasks: [], files: [], diff: [], branch: 'main', changes: '',
    stats: ['36s', '5.6k ↓  0.8k ↑', '$0.03'],
  },
  {
    project: 'notes-site', title: '修一下 RSS 输出', agent: 'Codex', when: '昨天', state: 'ended',
    msgs: [
      { u: 'RSS 里的日期格式不对，改成 RFC 822。' },
      { tool: '编辑', path: 'feed.ts', add: 3, del: 1 },
      { a: '改好了，日期现在按 RFC 822 输出，比如 Mon, 19 Oct 2026 08:00:00 +0800。' },
      { resume: true },
    ],
    tasks: [], files: [{ n: 'feed.ts', a: 3, d: 1 }], diff: [['del', '−  date.toISOString()'], ['add', '+  toRFC822(date)']],
    branch: 'main', changes: '已提交',
    stats: ['—', '—', '—'],
  },
  {
    project: 'notes-site', title: '首页标题调小一点', agent: 'Antigravity', when: '昨天', state: 'ended',
    msgs: [
      { u: '首页的大标题有点挤，字号调小一点。' },
      { a: '把首页标题从 40 调到了 34，行高跟着改成 1.2。' },
      { note: 'Antigravity 是实验性接入，暂不支持审批和打断。' },
      { resume: true },
    ],
    tasks: [], files: [{ n: 'index.css', a: 2, d: 2 }], diff: [['del', '−  font-size: 40px;'], ['add', '+  font-size: 34px;']],
    branch: 'main', changes: '1 处改动',
    stats: ['—', '—', '—'],
  },
];

let current = 0, mode = 'chat';
const listEl = $('#w-sessions'), chatEl = $('#w-chat'), termEl = $('#w-term'), scrollEl = $('#w-scroll');
const winCrab = makeCrab($('#w-crab'), 'idle');

function esc(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]); }
function sessionMood(s) { return s.thinking ? 'thinking' : MOOD[s.state]; }

function renderList() {
  let html = '', group = '';
  sessions.forEach((s, i) => {
    if (s.project !== group) {
      group = s.project;
      const n = sessions.filter(x => x.project === group).length;
      html += `<p class="w-group"><svg class="ic" aria-hidden="true"><use href="#i-folder"/></svg>${esc(group)}<span>${n}</span></p>`;
    }
    const badge = s.approval ? '<span class="badge">等你批准</span>' : '';
    html += `<button type="button" class="w-sess" data-i="${i}" aria-current="${i === current}"${s.unread ? ' data-unread' : ''}>`
      + `<i class="dot ${s.state === 'working' ? 'working' : s.state}"></i><span class="t">${esc(s.title)}</span>${badge}`
      + `<span class="s">${esc(s.agent)} · ${esc(s.when)}</span></button>`;
  });
  listEl.innerHTML = html;
}

function toolRow(m) {
  const delta = m.add != null ? ` <span class="add">+${m.add}</span> <span class="del">−${m.del}</span>` : '';
  const mark = m.running ? '<span class="pxstep on"><i></i><i></i><i></i></span>' : '<span class="sq"></span>';
  return `<p class="m-tool">${mark}${esc(m.tool)} <b>${esc(m.path)}</b>${delta}${m.result ? ` <span>${esc(m.result)}</span>` : ''}</p>`;
}
const TOOL_EN = { 读取: 'Read', 编辑: 'Update', 运行: 'Bash' };

function renderChat() {
  const s = sessions[current];
  chatEl.innerHTML = s.msgs.map(m => {
    if (m.u) return `<p class="m-user">${esc(m.u)}</p>`;
    if (m.a != null) return `<p class="m-ai">${esc(m.a)}</p>`;
    if (m.tool) return toolRow(m);
    if (m.note) return `<p class="m-note">${esc(m.note)}</p>`;
    if (m.resume) return `<p class="m-resume"><button type="button" class="w-btn" data-resume>继续「${esc(s.title)}」</button></p>`;
    return '';
  }).join('');
  const cli = s.agent;
  termEl.innerHTML = `<span class="d">${esc(cli)} · ~/${esc(s.project)}</span>\n\n` + s.msgs.map(m => {
    if (m.u) return `<span class="p">&gt;</span> ${esc(m.u)}\n\n`;
    if (m.a != null) return `<span class="d">⏺</span> ${esc(m.a)}\n\n`;
    if (m.tool) return `<span class="g">⏺</span> ${TOOL_EN[m.tool] || m.tool}(${esc(m.path)})${m.add != null ? ` <span class="g">+${m.add}</span> <span class="r">−${m.del}</span>` : ''}${m.running ? ' <span class="d">…</span>' : ''}\n\n`;
    if (m.note) return `<span class="d">${esc(m.note)}</span>\n\n`;
    return '';
  }).join('') + (s.state === 'ended' ? '' : '<span class="p">&gt;</span> ');
  scrollEl.scrollTop = scrollEl.scrollHeight;
}

function renderInspector() {
  const s = sessions[current];
  const done = s.tasks.filter(t => t.s === 'done').length;
  let html = `<p class="label">任务${s.tasks.length ? `<span>${done}/${s.tasks.length}</span>` : ''}</p>`;
  if (s.tasks.length) {
    html += `<div class="segbar">${s.tasks.map(t => `<i class="${t.s}"></i>`).join('')}</div>`;
    html += s.tasks.map(t => `<p class="task ${t.s}"><i class="cell ${t.s}"></i>${esc(t.t)}</p>`).join('');
  } else html += `<p class="empty">${EMPTY_TASKS}</p>`;
  html += `<p class="label">改动${s.files.length ? `<span>${s.files.length} files</span>` : ''}</p>`;
  if (s.files.length) {
    html += s.files.map(f => `<p class="file"><span>${esc(f.n)}</span><span><b class="add">+${f.a}</b> <b class="del">−${f.d}</b></span></p>`).join('');
    if (s.diff.length) html += `<div class="mini-diff">${s.diff.map(([k, l]) => `<p class="${k}">${esc(l)}</p>`).join('')}</div>`;
  } else html += `<p class="empty">${EMPTY_FILES}</p>`;
  html += `<p class="label">Git</p><p class="git"><svg class="ic" aria-hidden="true"><use href="#i-branch"/></svg>${esc(s.branch)}<em>${esc(s.changes)}</em></p>`;
  $('#w-insp').innerHTML = html;
  const mood = sessionMood(s);
  winCrab.set(mood);
  $('#w-mood').textContent = MOOD_TEXT[mood];
  $('#w-stats').innerHTML = ['工作', 'Token', '估算'].map((k, i) => `<dt>${k}</dt><dd>${esc(s.stats[i])}</dd>`).join('');
}

function renderChrome() {
  const s = sessions[current];
  $('#w-title').textContent = s.title;
  $('#w-agent').textContent = s.agent;
  $('#w-step').classList.toggle('on', s.state === 'working');
  const approve = $('#w-approve');
  approve.hidden = !s.approval;
  if (s.approval) $('#w-approve-text').textContent = `${s.agent} 在等你批准：${s.approval}`;
  $('#w-placeholder').textContent = s.state === 'ended' ? '会话已结束' : mode === 'term' ? `交给 ${s.agent}` : '继续说点什么…';
}

function render(i) {
  if (i != null && i !== current) return renderList();
  renderList(); renderChat(); renderInspector(); renderChrome();
}

listEl.addEventListener('click', e => {
  const b = e.target.closest('.w-sess');
  if (!b) return;
  current = +b.dataset.i;
  delete sessions[current].unread;
  render();
});
$$('[data-mode]').forEach(b => b.addEventListener('click', () => {
  mode = b.dataset.mode;
  $$('[data-mode]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
  chatEl.hidden = mode !== 'chat';
  termEl.hidden = mode !== 'term';
  render();
}));
chatEl.addEventListener('click', e => {
  if (!e.target.closest('[data-resume]')) return;
  const i = current, s = sessions[i];
  s.msgs = s.msgs.filter(m => !m.resume && !(m.note && s.agent !== 'Antigravity'));
  s.state = 'idle'; s.when = '刚刚';
  render();
});

/* Codex 那条：批准后编译，拒绝就停下 */
$('#w-approve').addEventListener('click', async e => {
  const b = e.target.closest('[data-approve]');
  if (!b) return;
  const i = current, s = sessions[i];
  const cmd = s.approval.replace(/^运行\s*/, '');
  s.approval = null;
  if (b.dataset.approve === 'no') {
    s.msgs.push({ note: `已拒绝：${cmd}` }, { a: '好，先不编译。要调整什么直接告诉我。' });
    s.state = 'waiting'; s.tasks[1].s = 'todo';
    return render(i);
  }
  const run = { tool: '运行', path: cmd, running: true };
  s.msgs.push(run); s.state = 'working';
  render(i);
  await sleep(1700);
  run.running = false; run.result = 'Build complete (12.4s)';
  s.msgs.push({ a: '编译通过，没有新的警告。' });
  s.tasks[1].s = 'done'; s.state = 'idle'; s.stats = ['1m 07s', '9.6k ↓  1.4k ↑', '$0.05'];
  render(i);
});
$('#w-approve').addEventListener('click', e => { if (e.target.closest('[data-approve]')) { approvedOnce = true; paintHint(); } }, true);

/* Claude 那条：进入视野后把一轮工作完整跑一遍 */
async function stream(i, msg, text) {
  for (let k = 1; k <= text.length; k += 2) {
    msg.a = text.slice(0, k);
    if (i === current) renderChat();
    await sleep(26);
  }
  msg.a = text;
  render(i);
}
async function runSidebarSession() {
  const i = 0, s = sessions[i];
  s.msgs = [{ u: '侧栏的间距有点挤，帮我整理一下。结构别动，改完我一起看。' }];
  s.state = 'working'; s.thinking = true;
  s.tasks = [{ t: '读侧栏的结构', s: 'doing' }, { t: '统一间距', s: 'todo' }, { t: '核对深色模式', s: 'todo' }];
  s.stats = ['3s', '1.2k ↓  0.1k ↑', '$0.01'];
  render(i);
  await sleep(1300);
  s.thinking = false;
  const a1 = { a: '' }; s.msgs.push(a1);
  await stream(i, a1, '我先看看侧栏现在是怎么排的。');
  await sleep(350);
  const read = { tool: '读取', path: 'Sources/Views/SidebarView.swift', running: true };
  s.msgs.push(read); render(i);
  await sleep(1100);
  read.running = false;
  s.tasks[0].s = 'done'; s.tasks[1].s = 'doing'; s.stats = ['24s', '6.8k ↓  0.6k ↑', '$0.04'];
  const edit = { tool: '编辑', path: 'SidebarView.swift', add: 8, del: 4, running: true };
  s.msgs.push(edit); render(i);
  await sleep(1300);
  edit.running = false;
  s.files = [{ n: 'SidebarView.swift', a: 8, d: 4 }];
  s.diff = [['del', '−  spacing: 14'], ['add', '+  spacing: 16'], ['del', '−  .padding(5)'], ['add', '+  .padding(6)']];
  s.changes = '1 处改动';
  s.tasks[1].s = 'done'; s.tasks[2].s = 'doing'; s.stats = ['1m 12s', '11.0k ↓  1.8k ↑', '$0.08'];
  render(i);
  await sleep(500);
  const a2 = { a: '' }; s.msgs.push(a2);
  await stream(i, a2, '间距都收进了 4pt 网格：分组之间 16，条目之间 6。深色模式下对比也看过了。改动在右边，有意见可以直接在 diff 的行上留。');
  s.tasks[2].s = 'done'; s.state = 'waiting'; s.stats = ['1m 48s', '12.4k ↓  2.1k ↑', '$0.09'];
  render(i);
}

/* 从「功能」那段 diff 发回的意见，会出现在窗口里的同一个会话 */
$('#send-back').addEventListener('click', async e => {
  const btn = e.currentTarget;
  btn.disabled = true;
  btn.textContent = '已发回「给侧栏收个尾」';
  const i = 0, s = sessions[i];
  if (s.state === 'working') return;
  s.msgs.push({ u: '第 42 行：分组之间再松一点，和顶上的搜索框对齐。' });
  s.state = 'working'; s.when = '刚刚';
  if (i !== current) s.unread = true;
  render(i);
  await sleep(1400);
  s.msgs.push({ tool: '编辑', path: 'SidebarView.swift', add: 2, del: 2 });
  s.files = [{ n: 'SidebarView.swift', a: 10, d: 6 }];
  render(i);
  await sleep(900);
  s.msgs.push({ a: '分组间距改成 20，左边和搜索框对齐了。' });
  s.state = 'waiting';
  render(i);
});

render();
let started = false;
new IntersectionObserver(([e], io) => {
  if (!e.isIntersecting || started) return;
  started = true; io.disconnect();
  setTimeout(runSidebarSession, reduceMotion ? 0 : 500);
}, { threshold: 0.35 }).observe($('#win'));

const narrow = matchMedia('(max-width: 760px)');
let approvedOnce = false;
function paintHint() {
  const where = narrow.matches ? '上面' : '左边';
  $('#stage-hint').textContent = approvedOnce ? `点${where}的会话切换，也可以切到终端视图看看。` : `点${where}的会话切换，Codex 那条在等你批准。`;
}
narrow.addEventListener('change', paintHint);
paintHint();

/* ───────── 功能：中文输入法 ───────── */
const IME = [
  { py: 'ce lan', c: ['侧栏', '册蓝', '测', '侧'] },
  { py: 'zai song', c: ['再松', '在松', '再', '在'] },
  { py: 'yi dian', c: ['一点', '一店', '以点', '一'] },
  { text: '，' },
  { py: 'sou suo kuang', c: ['搜索框', '搜索', '搜', '艘'] },
  { py: 'xia mian', c: ['下面', '夏眠', '下棉', '下'] },
  { py: 'liu', c: ['留', '流', '刘', '六'] },
  { text: ' 4pt。' },
];
const imeDone = $('#ime-done'), imePre = $('#ime-pre'), imeCands = $('#ime-cands');
let imeVisible = false;
new IntersectionObserver(([e]) => { imeVisible = e.isIntersecting; }).observe($('.demo-ime'));
async function runIme() {
  if (reduceMotion) { imeDone.textContent = '侧栏再松一点，搜索框下面留 4pt。'; return; }
  for (;;) {
    while (!imeVisible) await sleep(400);
    imeDone.textContent = ''; imePre.textContent = '';
    for (const seg of IME) {
      if (seg.text) { imeDone.textContent += seg.text; await sleep(260); continue; }
      imeCands.style.setProperty('--x', `${imePre.offsetLeft}px`);
      imeCands.style.setProperty('--y', `${imePre.offsetTop + 30}px`);
      for (let k = 1; k <= seg.py.length; k++) {
        imePre.textContent = seg.py.slice(0, k);
        imeCands.hidden = false;
        imeCands.innerHTML = seg.c.map((c, n) => `<span class="${n === 0 ? 'on' : ''}"><small>${n + 1}</small>${c}</span>`).join('');
        await sleep(seg.py[k - 1] === ' ' ? 40 : 95);
      }
      await sleep(420);
      imeCands.hidden = true;
      imePre.textContent = '';
      imeDone.textContent += seg.c[0];
      await sleep(180);
    }
    await sleep(2600);
  }
}
runIme();

/* ───────── 功能：小螃蟹 ───────── */
const bigCrab = makeCrab($('#big-crab'), 'working');
const moodButtons = $$('[data-mood]');
let moodAuto = !reduceMotion;
function setMood(mood) {
  bigCrab.set(mood);
  moodButtons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.mood === mood)));
}
moodButtons.forEach(b => b.addEventListener('click', () => { moodAuto = false; setMood(b.dataset.mood); }));
setInterval(() => {
  if (!moodAuto || !bigCrab.visible) return;
  const order = moodButtons.map(b => b.dataset.mood);
  setMood(order[(order.indexOf(bigCrab.mood) + 1) % order.length]);
}, 3400);

/* ───────── 复制构建命令 ───────── */
$('#copy-build').addEventListener('click', async () => {
  const text = $('#build-cmd').textContent;
  const status = $('#copy-status');
  try {
    if (!navigator.clipboard?.writeText) throw Error('no clipboard');
    await navigator.clipboard.writeText(text);
    status.textContent = '已复制。';
  } catch {
    const range = document.createRange();
    range.selectNodeContents($('#build-cmd'));
    const sel = getSelection(); sel.removeAllRanges(); sel.addRange(range);
    status.textContent = '已选中，按 ⌘C 复制。';
  }
});
})();
