"use strict";

const ICONS = {
  assistant: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 8h16v9a3 3 0 0 1-3 3H9l-5 2v-5Z"/><path d="M8 12h.01M12 12h.01M16 12h.01"/></svg>',
  overview: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="4" rx="1"/><rect x="14" y="11" width="7" height="10" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/></svg>',
  debts: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v14H4z"/><path d="M4 9h16M8 14h3M15 14h2"/></svg>',
  income: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v18M17 7.5c0-2-2-3-5-3s-5 1.3-5 3 1.7 2.7 5 3.5 5 1.8 5 3.8-2 3.7-5 3.7-5-1.5-5-3.5"/></svg>',
  refresh: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6v5h-5M4 18v-5h5"/><path d="M18.5 9A7 7 0 0 0 6 6.5L4 11m2 4a7 7 0 0 0 12 2.5l2-4.5"/></svg>',
  calendar: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/></svg>',
  wave: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10v4m4-8v12m4-16v20m4-15v10m4-7v4"/></svg>',
  mic: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M9 21h6"/></svg>',
  send: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 12 16-8-5 16-3-7Z"/><path d="m12 13 8-9"/></svg>',
  empty: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v14H4zM8 9h8M8 13h5"/></svg>',
  chevronLeft: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg>',
  chevronRight: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>'
};

const NAV_ITEMS = [
  { id: "assistant", label: "财务助理", title: "财务助理", kicker: "直接交代，确认后入账" },
  { id: "overview", label: "财务概览", title: "财务概览", kicker: "收入、债务与近期还款" },
  { id: "debts", label: "还款", title: "债务与还款", kicker: "滚动周期，不受月份限制" },
  { id: "income", label: "收入", title: "收入记录", kicker: "只统计已确认收入" }
];

const state = {
  token: sessionStorage.getItem("lh_finance_token") || "",
  page: "assistant",
  loading: false,
  summary: null,
  accounts: [],
  transactions: [],
  debts: [],
  actions: [],
  cashflow: [],
  horizon: 7,
  calendarMonth: startOfMonth(new Date()),
  selectedDate: "",
  expandedOwner: "",
  sending: false,
  listening: false,
  recognition: null,
  messages: [
    {
      role: "assistant",
      text: "告诉我一笔收入、支出、贷款或还款情况。我会先核对并生成待确认方案，只有你点击确认后才会写入。",
      suggestions: ["登记一笔收入", "我刚还了一笔贷款", "查看近 30 天还款"]
    }
  ]
};

const els = {
  loginScreen: document.getElementById("login-screen"),
  appShell: document.getElementById("app-shell"),
  loginForm: document.getElementById("login-form"),
  password: document.getElementById("password"),
  loginButton: document.getElementById("login-button"),
  loginError: document.getElementById("login-error"),
  passwordToggle: document.getElementById("password-toggle"),
  view: document.getElementById("view"),
  pageTitle: document.getElementById("page-title"),
  pageKicker: document.getElementById("page-kicker"),
  mobileNav: document.getElementById("mobile-nav"),
  desktopNav: document.getElementById("desktop-nav"),
  connection: document.getElementById("connection-status"),
  toast: document.getElementById("toast")
};

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function cents(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function money(value, compact = false) {
  const amount = cents(value) / 100;
  if (compact && Math.abs(amount) >= 10000) {
    return `${amount < 0 ? "-" : ""}¥${(Math.abs(amount) / 10000).toLocaleString("zh-CN", { maximumFractionDigits: 1 })}万`;
  }
  return new Intl.NumberFormat("zh-CN", {
    style: "currency", currency: "CNY", minimumFractionDigits: 0, maximumFractionDigits: 2
  }).format(amount);
}

function parseLocalDate(value) {
  if (!value) return null;
  const parts = String(value).slice(0, 10).split("-").map(Number);
  if (parts.length !== 3 || parts.some(Number.isNaN)) return null;
  return new Date(parts[0], parts[1] - 1, parts[2]);
}

function localISO(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function startOfDay(value) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function startOfMonth(value) {
  return new Date(value.getFullYear(), value.getMonth(), 1);
}

function addDays(value, days) {
  const result = new Date(value);
  result.setDate(result.getDate() + days);
  return result;
}

function daysInMonth(year, monthIndex) {
  return new Date(year, monthIndex + 1, 0).getDate();
}

function formatDate(value, includeYear = false) {
  const date = value instanceof Date ? value : parseLocalDate(value);
  if (!date) return "日期未登记";
  return new Intl.DateTimeFormat("zh-CN", includeYear
    ? { year: "numeric", month: "short", day: "numeric" }
    : { month: "short", day: "numeric" }).format(date);
}

function todayLabel() {
  return new Intl.DateTimeFormat("zh-CN", { month: "long", day: "numeric", weekday: "short" }).format(new Date());
}

function statusLabel(value) {
  return ({ confirmed: "已确认", paid: "已支付", planned: "计划中", overdue: "已逾期", cancelled: "已取消", open: "未偿还" })[value] || value || "未知";
}

function isFixedAsset(debt) {
  const text = `${debt.creditor || ""} ${debt.note || ""}`;
  return ["房贷", "住房贷款", "车贷", "汽车贷款"].some(term => text.includes(term));
}

function ownerName(debt) {
  const text = `${debt.note || ""} ${debt.creditor || ""}`;
  if (text.includes("老婆") || text.includes("妻子")) return "老婆";
  if (text.includes("合伙人")) return "合伙人";
  if (text.includes("父亲") || text.includes("爸爸") || text.includes("我爸")) return "父亲";
  const match = text.match(/(?:归属人|所属人|持有人)\s*[:：]\s*([^，,。;；\s]+)/);
  return match ? match[1] : "未分类";
}

function activeDebts() {
  return state.debts.filter(item => cents(item.outstanding_cents) > 0 && !["paid", "cancelled"].includes(item.status));
}

function operationalDebtTotal() {
  return activeDebts().filter(item => !isFixedAsset(item)).reduce((sum, item) => sum + cents(item.outstanding_cents), 0);
}

function fullDebtTotal() {
  return activeDebts().reduce((sum, item) => sum + cents(item.outstanding_cents), 0);
}

function paymentOnDate(debt, date) {
  const outstanding = cents(debt.outstanding_cents);
  if (outstanding <= 0) return 0;
  const firstDue = parseLocalDate(debt.due_on);
  const monthly = cents(debt.monthly_payment_cents);
  const day = Number(debt.payment_day) || (firstDue ? firstDue.getDate() : 0);
  if (monthly > 0 && day > 0) {
    const actualDay = Math.min(day, daysInMonth(date.getFullYear(), date.getMonth()));
    if (date.getDate() !== actualDay || (firstDue && startOfDay(date) < startOfDay(firstDue))) return 0;
    return Math.min(monthly, outstanding);
  }
  if (firstDue && localISO(firstDue) === localISO(date)) return outstanding;
  return 0;
}

function scheduledPayments(days = 30, from = startOfDay(new Date())) {
  const items = [];
  const debts = activeDebts();
  for (let offset = 0; offset <= days; offset += 1) {
    const date = addDays(from, offset);
    debts.forEach(debt => {
      const amount = paymentOnDate(debt, date);
      if (amount > 0) items.push({ debt, date, amount, offset });
    });
  }
  return items.sort((a, b) => a.date - b.date || String(a.debt.creditor).localeCompare(String(b.debt.creditor), "zh-CN"));
}

function groupOwners() {
  const groups = new Map();
  activeDebts().forEach(debt => {
    const owner = ownerName(debt);
    if (!groups.has(owner)) groups.set(owner, []);
    groups.get(owner).push(debt);
  });
  return [...groups.entries()].map(([owner, debts]) => ({
    owner,
    debts,
    operational: debts.filter(item => !isFixedAsset(item)).reduce((sum, item) => sum + cents(item.outstanding_cents), 0),
    full: debts.reduce((sum, item) => sum + cents(item.outstanding_cents), 0),
    fixed: debts.filter(isFixedAsset).reduce((sum, item) => sum + cents(item.outstanding_cents), 0)
  })).sort((a, b) => b.operational - a.operational || b.full - a.full);
}

async function api(path, options = {}) {
  const headers = { Accept: "application/json", ...(options.headers || {}) };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  if (options.body && !headers["Content-Type"]) headers["Content-Type"] = "application/json";
  const response = await fetch(path, { ...options, headers, cache: "no-store" });
  let payload = null;
  try { payload = await response.json(); } catch { payload = null; }
  if (response.status === 401 && !String(path).startsWith("/auth/")) {
    lockApp(false);
    throw new Error("登录已失效，请重新进入");
  }
  if (!response.ok) throw new Error(payload?.detail || `请求失败（${response.status}）`);
  return payload;
}

async function loadData(showFeedback = false) {
  if (!state.token || state.loading) return;
  state.loading = true;
  setConnection("loading");
  try {
    const [summary, accounts, transactions, debts, actions, cashflow] = await Promise.all([
      api("/dashboard/summary"),
      api("/finance/accounts"),
      api("/finance/transactions"),
      api("/finance/debts"),
      api("/assistant/actions?status=pending"),
      api("/dashboard/cashflow?days=90")
    ]);
    state.summary = summary;
    state.accounts = accounts.items || [];
    state.transactions = transactions.items || [];
    state.debts = debts.items || [];
    state.actions = (actions.items || []).filter(action => ["propose_finance_entry", "propose_debt_payment"].includes(action.action_type));
    state.cashflow = cashflow.points || [];
    setConnection("online");
    if (showFeedback) showToast("数据已刷新");
  } catch (error) {
    setConnection("offline");
    if (showFeedback) showToast(error.message, true);
    if (!state.summary) renderError(error.message);
  } finally {
    state.loading = false;
    if (state.summary) renderPage();
  }
}

function setConnection(mode) {
  els.connection.className = "connection-status";
  if (mode === "online") {
    els.connection.classList.add("online");
    els.connection.innerHTML = "<i></i>连接正常";
  } else if (mode === "offline") {
    els.connection.classList.add("offline");
    els.connection.innerHTML = "<i></i>连接异常";
  } else {
    els.connection.innerHTML = "<i></i>正在同步";
  }
}

function renderNav() {
  const html = NAV_ITEMS.map(item => `
    <button class="nav-button ${state.page === item.id ? "active" : ""}" data-page="${item.id}" aria-current="${state.page === item.id ? "page" : "false"}">
      ${ICONS[item.id]}<span>${item.label}</span>
    </button>`).join("");
  els.mobileNav.innerHTML = html;
  els.desktopNav.innerHTML = html;
}

function setPage(page) {
  if (!NAV_ITEMS.some(item => item.id === page)) return;
  state.page = page;
  renderNav();
  renderPage();
  els.view.focus({ preventScroll: true });
  window.scrollTo({ top: 0, behavior: "instant" });
}

function renderPage() {
  const meta = NAV_ITEMS.find(item => item.id === state.page) || NAV_ITEMS[0];
  els.pageTitle.textContent = meta.title;
  els.pageKicker.textContent = meta.kicker;
  els.view.classList.toggle("assistant-view", state.page === "assistant");
  if (!state.summary) {
    renderLoading();
    return;
  }
  if (state.page === "overview") renderOverview();
  else if (state.page === "debts") renderDebts();
  else if (state.page === "income") renderIncome();
  else renderAssistant();
}

function renderLoading() {
  els.view.innerHTML = '<div class="screen"><div class="skeleton"></div><div class="metric-grid"><div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div></div><div class="section skeleton" style="min-height:260px"></div></div>';
}

function renderError(message) {
  els.view.innerHTML = `<div class="surface error-panel"><strong>暂时无法读取财务数据</strong><p>${escapeHtml(message)}</p><button class="ghost-button" data-action="refresh">重新连接</button></div>`;
}

function sectionHeading(title, detail = "") {
  return `<div class="section-heading"><div><h2>${escapeHtml(title)}</h2>${detail ? `<p>${escapeHtml(detail)}</p>` : ""}</div></div>`;
}

function emptyState(title, detail) {
  return `<div class="surface empty-state">${ICONS.empty}<strong>${escapeHtml(title)}</strong><p>${escapeHtml(detail)}</p></div>`;
}

function horizonStrip() {
  return `<div class="horizon-strip" role="tablist" aria-label="还款周期">
    ${[3, 7, 15, 30].map(days => {
      const total = scheduledPayments(days).reduce((sum, item) => sum + item.amount, 0);
      return `<button class="horizon-button ${state.horizon === days ? "active" : ""}" data-horizon="${days}" role="tab" aria-selected="${state.horizon === days}"><span>近 ${days} 天</span><strong>${money(total, true)}</strong></button>`;
    }).join("")}
  </div>`;
}

function paymentList(days = state.horizon, limit = 20) {
  const items = scheduledPayments(days).slice(0, limit);
  if (!items.length) return emptyState(`近 ${days} 天没有已登记月供`, "有新的贷款或还款计划时，直接告诉财务助理。");
  return `<div class="surface list">${items.map(item => `
    <div class="list-row">
      <span class="status-dot ${item.offset <= 3 ? "danger" : "accent"}"></span>
      <div class="list-row-main"><p class="list-row-title">${escapeHtml(item.debt.creditor)}</p><p class="list-row-meta">${formatDate(item.date)} · ${item.offset === 0 ? "今天" : `${item.offset} 天后`} · ${isFixedAsset(item.debt) ? "固定资产月供" : "本期月供"}</p></div>
      <span class="list-row-value">${money(item.amount)}</span>
    </div>`).join("")}</div>`;
}

function renderOwnerCards() {
  const groups = groupOwners();
  if (!groups.length) return emptyState("还没有债务归属人", "通过财务助理登记债权人、归属人和还款信息。");
  return `<div class="people-grid">${groups.map(group => {
    const open = state.expandedOwner === group.owner;
    return `<article class="person-card">
      <button class="person-toggle" data-owner="${escapeHtml(group.owner)}" aria-expanded="${open}">
        <div class="person-head"><div><h3>${escapeHtml(group.owner)}</h3><p>${group.debts.length} 笔债务${group.fixed ? ` · 含固定资产 ${money(group.fixed, true)}` : ""}</p></div><strong>${money(group.operational || group.full, true)}</strong></div>
        ${group.fixed ? `<p>完整合计 ${money(group.full)}，主金额已剔除房贷、车贷</p>` : ""}
      </button>
      ${open ? `<div class="person-details">${group.debts.map(debt => `<div class="list-row"><div class="list-row-main"><p class="list-row-title">${escapeHtml(debt.creditor)}${isFixedAsset(debt) ? '<span class="asset-tag">固定资产</span>' : ""}</p><p class="list-row-meta">${debt.monthly_payment_cents ? `月供 ${money(debt.monthly_payment_cents)}` : "月供未登记"}${debt.payment_day ? ` · 每月 ${debt.payment_day} 日` : ""}</p></div><span class="list-row-value">${money(debt.outstanding_cents)}</span></div>`).join("")}</div>` : ""}
    </article>`;
  }).join("")}</div>`;
}

function renderOverview() {
  const s = state.summary;
  const horizonItems = scheduledPayments(30);
  const nextPayment = horizonItems[0];
  const fixed = fullDebtTotal() - operationalDebtTotal();
  els.view.innerHTML = `<div class="screen">
    <div class="screen-intro"><div><h2>今天的财务底盘</h2><p>收入独立累计，还款只减少对应债务余额。</p></div><span class="date-chip">${todayLabel()}</span></div>
    <section class="hero-finance" aria-label="已登记收入">
      <p class="hero-label">已登记收入</p>
      <p class="hero-amount">${money(s.registered_income_cents)}</p>
      <p class="hero-note">仅统计已确认收入，不因还款或支出减少</p>
      <div class="hero-footer">
        <div><span>经营性未偿债务</span><strong>${money(operationalDebtTotal(), true)}</strong></div>
        <div><span>下一笔还款</span><strong>${nextPayment ? `${formatDate(nextPayment.date)} · ${money(nextPayment.amount, true)}` : "暂无"}</strong></div>
      </div>
    </section>
    <div class="metric-grid">
      <div class="metric attention"><span>近 30 天需还</span><strong>${money(horizonItems.reduce((sum, item) => sum + item.amount, 0), true)}</strong><small>按今天向后滚动，包含跨月日期</small></div>
      <div class="metric"><span>未偿债务</span><strong>${money(operationalDebtTotal(), true)}</strong><small>${fixed ? `完整合计 ${money(fullDebtTotal(), true)}，含房贷、车贷` : "不含已还清债务"}</small></div>
      <div class="metric"><span>计划收入</span><strong>${money(s.planned_income_cents, true)}</strong><small>${s.overdue_income_cents ? `其中逾期 ${money(s.overdue_income_cents, true)}` : "当前没有逾期收入"}</small></div>
    </div>
    <section class="section">${sectionHeading("近期要还", "点击周期查看对应明细")}${horizonStrip()}</section>
    <section class="section">${paymentList()}</section>
    <div class="overview-columns">
      <section class="section">${sectionHeading("还款日历", "有标记的日期存在还款")}${renderCalendar()}</section>
      <section class="section">${sectionHeading("按人查看", "点击展开每个人的债务")}${renderOwnerCards()}</section>
    </div>
  </div>`;
}

function calendarPayments(month) {
  const first = startOfMonth(month);
  const last = new Date(first.getFullYear(), first.getMonth() + 1, 0);
  const days = Math.round((last - first) / 86400000);
  return scheduledPayments(days, first);
}

function renderCalendar() {
  const month = state.calendarMonth;
  const y = month.getFullYear();
  const m = month.getMonth();
  const firstWeekday = new Date(y, m, 1).getDay();
  const currentDays = daysInMonth(y, m);
  const previousDays = daysInMonth(y, m - 1);
  const payments = calendarPayments(month);
  const byDate = new Map();
  payments.forEach(item => {
    const key = localISO(item.date);
    if (!byDate.has(key)) byDate.set(key, []);
    byDate.get(key).push(item);
  });
  if (!state.selectedDate || !state.selectedDate.startsWith(`${y}-${String(m + 1).padStart(2, "0")}`)) {
    state.selectedDate = payments[0] ? localISO(payments[0].date) : "";
  }
  const cells = [];
  for (let i = firstWeekday - 1; i >= 0; i -= 1) {
    const d = new Date(y, m - 1, previousDays - i);
    cells.push({ date: d, muted: true });
  }
  for (let day = 1; day <= currentDays; day += 1) cells.push({ date: new Date(y, m, day), muted: false });
  while (cells.length < 42) cells.push({ date: new Date(y, m + 1, cells.length - firstWeekday - currentDays + 1), muted: true });
  const today = localISO(new Date());
  const selectedItems = byDate.get(state.selectedDate) || [];
  return `<div class="surface calendar">
    <div class="calendar-head"><strong>${y} 年 ${m + 1} 月</strong><div class="calendar-nav"><button class="icon-button" data-month="-1" aria-label="上个月">${ICONS.chevronLeft}</button><button class="icon-button" data-month="1" aria-label="下个月">${ICONS.chevronRight}</button></div></div>
    <div class="calendar-week"><span>日</span><span>一</span><span>二</span><span>三</span><span>四</span><span>五</span><span>六</span></div>
    <div class="calendar-grid">${cells.map(cell => {
      const key = localISO(cell.date);
      return `<button class="calendar-day ${cell.muted ? "muted" : ""} ${key === today ? "today" : ""} ${byDate.has(key) ? "has-payment" : ""} ${key === state.selectedDate ? "selected" : ""}" data-date="${key}" aria-label="${formatDate(cell.date, true)}${byDate.has(key) ? "有还款" : ""}">${cell.date.getDate()}</button>`;
    }).join("")}</div>
    ${state.selectedDate ? `<div class="calendar-detail"><div class="calendar-detail-head"><span>${formatDate(state.selectedDate)} 应还</span><span>${money(selectedItems.reduce((sum, item) => sum + item.amount, 0))}</span></div>${selectedItems.length ? selectedItems.map(item => `<div class="list-row"><div class="list-row-main"><p class="list-row-title">${escapeHtml(item.debt.creditor)}</p><p class="list-row-meta">${isFixedAsset(item.debt) ? "固定资产月供" : "本期月供"}</p></div><span class="list-row-value">${money(item.amount)}</span></div>`).join("") : '<p class="list-row-meta">当天没有待还款项</p>'}</div>` : ""}
  </div>`;
}

function renderDebts() {
  const debts = activeDebts();
  const fixed = fullDebtTotal() - operationalDebtTotal();
  els.view.innerHTML = `<div class="screen">
    <div class="screen-intro"><div><h2>债务与还款</h2><p>月供按今天向后滚动计算，不受自然月限制。</p></div><button class="ghost-button" data-assistant-prompt="登记一笔新的债务">交代新债务</button></div>
    <div class="surface debt-summary-line"><div><p>经营性未偿债务</p><strong>${money(operationalDebtTotal())}</strong></div><small>${fixed ? `另有固定资产贷款 ${money(fixed)}；完整合计 ${money(fullDebtTotal())}` : "当前没有单列的房贷或车贷"}</small></div>
    <section class="section">${sectionHeading("近期要还", "选择 3、7、15 或 30 天")}${horizonStrip()}<div style="margin-top:10px">${paymentList()}</div></section>
    <div class="debt-layout">
      <section class="section">${sectionHeading("全部未偿债务", `${debts.length} 笔`)}${debts.length ? `<div class="surface">${debts.map(debt => `<article class="debt-card"><div class="debt-card-head"><h3>${escapeHtml(debt.creditor)}${isFixedAsset(debt) ? '<span class="asset-tag">固定资产</span>' : ""}</h3><strong>${money(debt.outstanding_cents)}</strong></div><div class="debt-card-grid"><div><span>原始本金</span><b>${money(debt.principal_cents, true)}</b></div><div><span>每月还款</span><b>${debt.monthly_payment_cents ? money(debt.monthly_payment_cents, true) : "未登记"}</b></div><div><span>还款日</span><b>${debt.payment_day ? `每月 ${debt.payment_day} 日` : formatDate(debt.due_on)}</b></div></div></article>`).join("")}</div>` : emptyState("还没有未偿债务", "通过财务助理交代债权人、本金、月供和还款日。")}</section>
      <section class="section">${sectionHeading("还款日历", "点击日期查看明细")}${renderCalendar()}</section>
    </div>
  </div>`;
}

function confirmedIncome() {
  return state.transactions.filter(item => item.kind === "income" && ["confirmed", "paid"].includes(item.status));
}

function renderIncome() {
  const items = confirmedIncome();
  const now = new Date();
  const monthPrefix = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  const monthItems = items.filter(item => String(item.occurred_on).startsWith(monthPrefix));
  const grouped = new Map();
  items.forEach(item => {
    const key = String(item.occurred_on).slice(0, 7);
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(item);
  });
  els.view.innerHTML = `<div class="screen">
    <div class="screen-intro"><div><h2>收入记录</h2><p>这里只累计收入；支出和还款不会把历史收入扣掉。</p></div><button class="secondary-button" data-assistant-prompt="登记一笔收入">登记收入</button></div>
    <div class="income-layout">
      <section class="section"><div class="surface income-hero"><div><span>累计已登记收入</span><strong>${money(state.summary.registered_income_cents)}</strong></div><div><span>本月收入</span><strong>${money(monthItems.reduce((sum, item) => sum + cents(item.amount_cents), 0))}</strong></div></div><div class="metric-grid"><div class="metric"><span>收入笔数</span><strong>${items.length} 笔</strong><small>已确认或已支付</small></div><div class="metric"><span>计划收入</span><strong>${money(state.summary.planned_income_cents, true)}</strong><small>尚未计入累计收入</small></div></div></section>
      <section class="section">${sectionHeading("收入明细", items.length ? `共 ${items.length} 笔` : "")}${items.length ? `<div class="surface list">${[...grouped.entries()].map(([month, list]) => `<div class="month-divider">${month.replace("-", " 年 ")} 月</div>${list.map(item => `<div class="list-row"><span class="status-dot success"></span><div class="list-row-main"><p class="list-row-title">${escapeHtml(item.counterparty || item.note || "收入")}</p><p class="list-row-meta">${formatDate(item.occurred_on, true)} · ${statusLabel(item.status)}</p></div><span class="list-row-value">+${money(item.amount_cents)}</span></div>`).join("")}`).join("")}</div>` : emptyState("还没有收入记录", "告诉财务助理收入金额、来源和日期，确认后即可登记。")}</section>
    </div>
  </div>`;
}

function actionSummary(action) {
  const p = action.payload || {};
  if (action.action_type === "propose_finance_entry") {
    const kind = p.kind === "income" ? "收入" : "支出";
    return `${kind} ${money(p.amount_cents)}${p.counterparty ? ` · ${p.counterparty}` : ""}${p.occurred_on ? ` · ${formatDate(p.occurred_on)}` : ""}`;
  }
  if (action.action_type === "propose_debt_payment") {
    return `偿还 ${p.creditor || "债务"} ${money(p.payment_cents)}${p.new_outstanding_cents != null ? ` · 剩余 ${money(p.new_outstanding_cents)}` : ""}`;
  }
  return "AI 已整理出一份财务登记方案";
}

function richText(value) {
  const lines = String(value || "").replace(/\r/g, "").split("\n");
  let output = "";
  let inList = false;
  const inline = raw => escapeHtml(raw)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/__(.+?)__/g, "<strong>$1</strong>")
    .replace(/`(.+?)`/g, "$1")
    .replace(/\*/g, "");
  lines.forEach(raw => {
    const line = raw.trim().replace(/^#{1,6}\s*/, "");
    const bullet = line.match(/^[-*•]\s+(.+)/);
    if (bullet) {
      if (!inList) { output += "<ul>"; inList = true; }
      output += `<li>${inline(bullet[1])}</li>`;
    } else {
      if (inList) { output += "</ul>"; inList = false; }
      if (line) output += `<p>${inline(line)}</p>`;
    }
  });
  if (inList) output += "</ul>";
  return output || "<p>已完成核对。</p>";
}

function renderMessages() {
  const messages = state.messages.map((message, index) => `
    <div class="message ${message.role} ${message.error ? "error" : ""}">
      ${message.role === "assistant" ? `<span class="assistant-avatar">${ICONS.wave}</span>` : ""}
      <div class="bubble-wrap"><p class="message-label">${message.role === "user" ? "你" : "洛浩财务助理"}</p><div class="bubble">${richText(message.text)}</div>
      ${message.role === "assistant" && message.suggestions?.length && index === state.messages.length - 1 ? `<div class="message-actions">${message.suggestions.map(item => `<button data-chat-prompt="${escapeHtml(item)}">${escapeHtml(item)}</button>`).join("")}</div>` : ""}
      </div>
    </div>`).join("");
  return messages + (state.sending ? `<div class="message assistant"><span class="assistant-avatar">${ICONS.wave}</span><div class="bubble-wrap"><p class="message-label">正在核对数据</p><div class="bubble"><span class="typing"><i></i><i></i><i></i></span></div></div></div>` : "");
}

function renderPendingActions() {
  if (!state.actions.length) return "";
  return `<div class="pending-stack" aria-label="待确认财务操作">${state.actions.map(action => `<article class="pending-card"><h3>${action.action_type === "propose_debt_payment" ? "待确认还款" : "待确认财务登记"}</h3><p>${escapeHtml(actionSummary(action))}</p><div class="pending-actions"><button class="secondary-button" data-confirm-action="${action.id}">确认登记</button><button class="ghost-button" data-cancel-action="${action.id}">返回修改</button></div></article>`).join("")}</div>`;
}

function renderAssistant() {
  els.view.innerHTML = `<div class="screen assistant-layout">
    <div class="assistant-status"><span class="assistant-avatar">${ICONS.wave}</span><div><strong>财务模式</strong><p>${state.actions.length ? `有 ${state.actions.length} 项方案等待你确认。` : `当前已登记收入 ${money(state.summary.registered_income_cents)}，经营性未偿债务 ${money(operationalDebtTotal())}。`}写入前始终由你确认。</p></div></div>
    <div class="quick-prompts"><button class="quick-prompt" data-chat-prompt="登记一笔收入">登记收入</button><button class="quick-prompt" data-chat-prompt="我刚还了一笔贷款">登记还款</button><button class="quick-prompt" data-chat-prompt="查看近 30 天要还多少钱">近期还款</button><button class="quick-prompt" data-chat-prompt="分析我现在的财务风险">风险分析</button></div>
    <div class="messages">${renderMessages()}</div>
    ${renderPendingActions()}
    <div id="chat-bottom"></div>
    <form id="composer" class="composer"><div class="composer-inner"><button class="voice-button ${state.listening ? "listening" : ""}" type="button" data-action="voice" aria-label="${state.listening ? "停止语音输入" : "开始语音输入"}">${ICONS.mic}</button><textarea id="composer-input" rows="1" placeholder="输入，或点击麦克风说话" aria-label="向财务助理交代"></textarea><button class="send-button" type="submit" aria-label="发送" disabled>${ICONS.send}</button></div></form>
  </div>`;
  const input = document.getElementById("composer-input");
  const form = document.getElementById("composer");
  const send = form.querySelector(".send-button");
  input.addEventListener("input", () => {
    send.disabled = !input.value.trim() || state.sending;
    input.style.height = "44px";
    input.style.height = `${Math.min(input.scrollHeight, 120)}px`;
  });
  input.addEventListener("keydown", event => {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") form.requestSubmit();
  });
  form.addEventListener("submit", event => {
    event.preventDefault();
    const text = input.value.trim();
    if (text) sendAssistant(text);
  });
  requestAnimationFrame(() => document.getElementById("chat-bottom")?.scrollIntoView({ block: "end" }));
}

async function sendAssistant(text) {
  if (!text.trim() || state.sending) return;
  const history = state.messages.filter(item => !item.error).slice(-16).map(item => ({ role: item.role, content: item.text }));
  state.messages.push({ role: "user", text: text.trim() });
  state.sending = true;
  renderAssistant();
  try {
    const result = await api("/assistant/command", {
      method: "POST",
      body: JSON.stringify({ text: text.trim(), mode: "finance", history })
    });
    state.messages.push({ role: "assistant", text: result.reply || "已核对完成。", suggestions: result.suggestions || [] });
    const actions = await api("/assistant/actions?status=pending");
    state.actions = (actions.items || []).filter(action => ["propose_finance_entry", "propose_debt_payment"].includes(action.action_type));
  } catch (error) {
    state.messages.push({ role: "assistant", text: `这次没有完成：${error.message}`, error: true, suggestions: ["重新发送"] });
  } finally {
    state.sending = false;
    if (state.token) renderAssistant();
  }
}

async function resolveAction(id, confirm) {
  const action = state.actions.find(item => item.id === id);
  if (!action) return;
  try {
    await api(`/assistant/actions/${id}/${confirm ? "confirm" : "cancel"}`, { method: "POST" });
    state.actions = state.actions.filter(item => item.id !== id);
    state.messages.push({ role: "assistant", text: confirm ? "已经正式写入，并同步更新了收入或债务数据。" : "这份方案已取消。请直接告诉我需要修改的内容。" });
    if (confirm) await loadData();
    else renderAssistant();
    showToast(confirm ? "登记成功" : "方案已取消");
  } catch (error) {
    showToast(error.message, true);
    state.messages.push({ role: "assistant", text: `操作没有完成：${error.message}`, error: true });
    renderAssistant();
  }
}

function startVoice() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    showToast("当前浏览器不支持语音识别，请使用 Safari 或直接输入", true);
    return;
  }
  if (state.recognition && state.listening) {
    state.recognition.stop();
    return;
  }
  const recognition = new SpeechRecognition();
  state.recognition = recognition;
  recognition.lang = "zh-CN";
  recognition.continuous = false;
  recognition.interimResults = true;
  recognition.onstart = () => { state.listening = true; document.querySelector(".voice-button")?.classList.add("listening"); };
  recognition.onresult = event => {
    let text = "";
    for (let i = event.resultIndex; i < event.results.length; i += 1) text += event.results[i][0].transcript;
    const input = document.getElementById("composer-input");
    if (input) {
      input.value = text;
      input.dispatchEvent(new Event("input"));
    }
  };
  recognition.onerror = event => {
    if (event.error !== "aborted") showToast(event.error === "not-allowed" ? "请允许麦克风权限后再试" : "语音识别没有完成，请重试", true);
  };
  recognition.onend = () => {
    state.listening = false;
    state.recognition = null;
    document.querySelector(".voice-button")?.classList.remove("listening");
  };
  recognition.start();
}

function showToast(message, error = false) {
  clearTimeout(showToast.timer);
  els.toast.textContent = message;
  els.toast.className = `toast show${error ? " error" : ""}`;
  showToast.timer = setTimeout(() => { els.toast.className = "toast"; }, 2600);
}

async function login(password) {
  if (password.length !== 2 || state.loading) return;
  state.loading = true;
  els.loginButton.textContent = "正在验证…";
  els.loginError.textContent = "";
  try {
    const result = await api("/auth/login", { method: "POST", body: JSON.stringify({ password }) });
    state.token = result.access_token;
    sessionStorage.setItem("lh_finance_token", state.token);
    els.loginScreen.hidden = true;
    els.appShell.hidden = false;
    state.loading = false;
    renderNav();
    renderLoading();
    await loadData();
    setPage("assistant");
  } catch (error) {
    state.loading = false;
    els.loginError.textContent = error.message === "invalid password" ? "密码不正确，请重新输入" : error.message;
    els.password.value = "";
    els.password.focus();
  } finally {
    els.loginButton.textContent = "进入驾驶舱";
  }
}

function lockApp(showMessage = true) {
  if (state.recognition) state.recognition.abort();
  state.token = "";
  sessionStorage.removeItem("lh_finance_token");
  els.appShell.hidden = true;
  els.loginScreen.hidden = false;
  els.password.value = "";
  els.loginButton.classList.remove("ready");
  els.loginButton.disabled = true;
  els.loginError.textContent = "";
  if (showMessage) showToast("已锁定");
  setTimeout(() => els.password.focus(), 60);
}

els.loginForm.addEventListener("submit", event => {
  event.preventDefault();
  login(els.password.value.trim());
});

els.password.addEventListener("input", () => {
  els.password.value = els.password.value.replace(/\D/g, "").slice(0, 8);
  els.loginButton.classList.toggle("ready", els.password.value.length > 0);
  els.loginButton.disabled = els.password.value.length === 0;
  els.loginError.textContent = "";
  if (els.password.value.length === 2) setTimeout(() => login(els.password.value), 120);
});

els.passwordToggle.addEventListener("click", () => {
  const reveal = els.password.type === "password";
  els.password.type = reveal ? "text" : "password";
  els.passwordToggle.setAttribute("aria-label", reveal ? "隐藏密码" : "显示密码");
});

document.addEventListener("click", event => {
  const pageButton = event.target.closest("[data-page]");
  if (pageButton) { setPage(pageButton.dataset.page); return; }
  const action = event.target.closest("[data-action]")?.dataset.action;
  if (action === "lock") { lockApp(); return; }
  if (action === "refresh") { loadData(true); return; }
  if (action === "voice") { startVoice(); return; }
  const horizon = event.target.closest("[data-horizon]");
  if (horizon) { state.horizon = Number(horizon.dataset.horizon); renderPage(); return; }
  const month = event.target.closest("[data-month]");
  if (month) { state.calendarMonth = new Date(state.calendarMonth.getFullYear(), state.calendarMonth.getMonth() + Number(month.dataset.month), 1); state.selectedDate = ""; renderPage(); return; }
  const date = event.target.closest("[data-date]");
  if (date) { state.selectedDate = date.dataset.date; renderPage(); return; }
  const owner = event.target.closest("[data-owner]");
  if (owner) { state.expandedOwner = state.expandedOwner === owner.dataset.owner ? "" : owner.dataset.owner; renderPage(); return; }
  const assistantPrompt = event.target.closest("[data-assistant-prompt]");
  if (assistantPrompt) { setPage("assistant"); setTimeout(() => sendAssistant(assistantPrompt.dataset.assistantPrompt), 0); return; }
  const chatPrompt = event.target.closest("[data-chat-prompt]");
  if (chatPrompt) { sendAssistant(chatPrompt.dataset.chatPrompt); return; }
  const confirm = event.target.closest("[data-confirm-action]");
  if (confirm) { resolveAction(Number(confirm.dataset.confirmAction), true); return; }
  const cancel = event.target.closest("[data-cancel-action]");
  if (cancel) resolveAction(Number(cancel.dataset.cancelAction), false);
});

window.addEventListener("pagehide", () => {
  if (state.token) lockApp(false);
});

window.addEventListener("pageshow", event => {
  if (event.persisted && state.token) lockApp(false);
});

window.addEventListener("online", () => state.token && loadData());
window.addEventListener("offline", () => setConnection("offline"));

async function boot() {
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
  renderNav();
  if (!state.token) {
    els.password.focus();
    return;
  }
  els.loginScreen.hidden = true;
  els.appShell.hidden = false;
  renderLoading();
  await loadData();
}

boot();
