const telemetry = {
  "24h": {
    latency: [690, 640, 650, 622, 590, 604, 612],
    quality: [96.8, 97.4, 97.1, 98.1, 98.0, 98.4, 98.2],
    requests: [920, 1120, 1040, 1225, 1360, 1288, 1410],
    cost: 96,
    incidents: 1
  },
  "7d": {
    latency: [720, 705, 660, 648, 630, 618, 612],
    quality: [96.2, 96.8, 97.4, 97.2, 97.8, 98.0, 98.2],
    requests: [4850, 5260, 6010, 6420, 6900, 7340, 7680],
    cost: 428,
    incidents: 2
  },
  "30d": {
    latency: [810, 790, 760, 734, 702, 668, 640],
    quality: [94.4, 95.2, 96.1, 96.9, 97.1, 97.7, 98.0],
    requests: [18200, 19400, 21300, 23800, 26100, 28400, 30900],
    cost: 1840,
    incidents: 4
  }
};

const runs = [
  {
    id: "run-1048",
    title: "Retrieval summary",
    flow: "support-rag",
    model: "gpt-4.1",
    status: "healthy",
    latency: 612,
    cost: 12.4,
    quality: 98.4,
    owner: "Ops",
    guardrail: "Groundedness",
    tokens: "18.4k",
    budget: "92%",
    signals: [
      ["Groundedness", 94, "ok"],
      ["Refusal fit", 88, "ok"],
      ["Latency budget", 79, "ok"]
    ]
  },
  {
    id: "run-1047",
    title: "Invoice extraction",
    flow: "finance-agent",
    model: "gpt-4.1-mini",
    status: "watch",
    latency: 845,
    cost: 8.1,
    quality: 94.9,
    owner: "Finance",
    guardrail: "Schema match",
    tokens: "9.7k",
    budget: "76%",
    signals: [
      ["Schema match", 91, "ok"],
      ["Latency budget", 63, "warn"],
      ["Retry rate", 18, "warn"]
    ]
  },
  {
    id: "run-1046",
    title: "Policy answer",
    flow: "legal-copilot",
    model: "o4-mini",
    status: "incident",
    latency: 1180,
    cost: 16.8,
    quality: 87.2,
    owner: "Risk",
    guardrail: "Citation required",
    tokens: "26.1k",
    budget: "41%",
    signals: [
      ["Citation coverage", 58, "bad"],
      ["Hallucination risk", 38, "bad"],
      ["Latency budget", 55, "warn"]
    ]
  },
  {
    id: "run-1045",
    title: "Search ranking",
    flow: "growth-eval",
    model: "gpt-4.1-mini",
    status: "healthy",
    latency: 488,
    cost: 4.9,
    quality: 97.6,
    owner: "Growth",
    guardrail: "Preference eval",
    tokens: "6.2k",
    budget: "96%",
    signals: [
      ["Preference win", 89, "ok"],
      ["Latency budget", 91, "ok"],
      ["Cost budget", 86, "ok"]
    ]
  },
  {
    id: "run-1044",
    title: "Agent handoff",
    flow: "code-review",
    model: "gpt-4.1",
    status: "watch",
    latency: 702,
    cost: 19.3,
    quality: 95.1,
    owner: "Platform",
    guardrail: "Tool safety",
    tokens: "31.5k",
    budget: "69%",
    signals: [
      ["Tool safety", 99, "ok"],
      ["Cost budget", 64, "warn"],
      ["Completion rate", 84, "ok"]
    ]
  }
];

const viewCopy = {
  overview: "Overview",
  models: "Models",
  accounts: "Accounts",
  runs: "Runs",
  alerts: "Alerts"
};

let selectedStatus = "all";
let selectedRunId = runs[0].id;
let chartMode = "latency";
let paused = false;

const rangeSelect = document.querySelector("#range-select");
const modelSelect = document.querySelector("#model-select");
const headerActions = document.querySelector(".header-actions");
const metricsGrid = document.querySelector(".metrics-grid");
const accountGrid = document.querySelector(".account-status-grid");
const dashboardGrid = document.querySelector(".dashboard-grid");
const runsPanel = document.querySelector(".runs-panel");
const runsTable = document.querySelector("#runs-table");
const chartWrap = document.querySelector("#chart-wrap");
const pauseButton = document.querySelector("#pause-monitor");
const checkCodexButton = document.querySelector("#check-codex");
const checkOpenRouterButton = document.querySelector("#check-openrouter");
const clearOpenRouterKeyButton = document.querySelector("#clear-openrouter-key");
const openRouterKeyInput = document.querySelector("#openrouter-key");

function filteredRuns() {
  const model = modelSelect.value;
  return runs.filter((run) => {
    const matchesStatus = selectedStatus === "all" || run.status === selectedStatus;
    const matchesModel = model === "all" || run.model === model;
    return matchesStatus && matchesModel;
  });
}

function formatCurrency(value) {
  return `$${value.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;
}

function formatCredits(value) {
  if (value == null || Number.isNaN(Number(value))) {
    return "-";
  }
  return `$${Number(value).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
}

function formatPercent(value) {
  if (value == null || Number.isNaN(Number(value))) {
    return "-";
  }
  return `${Math.round(Number(value))}%`;
}

function formatDuration(seconds) {
  if (seconds == null || Number.isNaN(Number(seconds))) {
    return "-";
  }
  const clamped = Math.max(0, Number(seconds));
  const days = Math.floor(clamped / 86400);
  const hours = Math.floor((clamped % 86400) / 3600);
  const minutes = Math.floor((clamped % 3600) / 60);
  if (days > 0) {
    return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
  }
  if (hours > 0) {
    return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  }
  return `${Math.max(1, minutes)}m`;
}

function formatCheckedAt(value) {
  if (!value) {
    return "not checked";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "just checked";
  }
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function renderMetrics() {
  const data = telemetry[rangeSelect.value];
  document.querySelector("#metric-latency").textContent = `${Math.round(data.latency.at(-1))}ms`;
  document.querySelector("#metric-cost").textContent = formatCurrency(data.cost);
  document.querySelector("#metric-quality").textContent = `${data.quality.at(-1).toFixed(1)}%`;
  document.querySelector("#metric-incidents").textContent = `${data.incidents}`;
}

function renderChart() {
  const data = telemetry[rangeSelect.value];
  const series = data[chartMode];
  const bars = data.requests;
  const width = 720;
  const height = 250;
  const padding = { top: 18, right: 20, bottom: 26, left: 38 };
  const plotW = width - padding.left - padding.right;
  const plotH = height - padding.top - padding.bottom;
  const min = Math.min(...series) * 0.96;
  const max = Math.max(...series) * 1.04;
  const maxBar = Math.max(...bars);

  const points = series.map((value, index) => {
    const x = padding.left + (plotW / (series.length - 1)) * index;
    const y = padding.top + plotH - ((value - min) / (max - min)) * plotH;
    return [x, y, value];
  });

  const line = points.map(([x, y], index) => `${index === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`).join(" ");
  const grid = [0, 1, 2, 3].map((tick) => {
    const y = padding.top + (plotH / 3) * tick;
    return `<line class="chart-grid" x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}"></line>`;
  }).join("");

  const barW = Math.max(18, plotW / bars.length - 22);
  const barMarkup = bars.map((value, index) => {
    const x = padding.left + (plotW / bars.length) * index + 8;
    const h = Math.max(18, (value / maxBar) * (plotH * 0.55));
    const y = padding.top + plotH - h;
    return `<rect class="chart-bar" x="${x}" y="${y}" width="${barW}" height="${h}" rx="7"></rect>`;
  }).join("");

  const dots = points.map(([x, y]) => `<circle class="chart-dot" cx="${x}" cy="${y}" r="4"></circle>`).join("");

  chartWrap.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${chartMode} trend chart">
      ${grid}
      ${barMarkup}
      <path class="chart-line" d="${line}"></path>
      ${dots}
      <text class="axis-label" x="${padding.left}" y="${height - 4}">Mon</text>
      <text class="axis-label" x="${width / 2 - 12}" y="${height - 4}">Thu</text>
      <text class="axis-label" x="${width - padding.right - 24}" y="${height - 4}">Sun</text>
    </svg>
  `;
}

function renderRuns() {
  const rows = filteredRuns();
  if (!rows.some((run) => run.id === selectedRunId) && rows[0]) {
    selectedRunId = rows[0].id;
  }

  runsTable.innerHTML = rows.map((run) => `
    <tr class="${run.id === selectedRunId ? "is-selected" : ""}" data-run-id="${run.id}" tabindex="0">
      <td>
        <span class="run-title">
          <strong>${run.title}</strong>
          <span>${run.id} · ${run.flow}</span>
        </span>
      </td>
      <td class="model-cell">${run.model}</td>
      <td><span class="status-badge ${run.status}">${run.status}</span></td>
      <td>${run.latency}ms</td>
      <td>$${run.cost.toFixed(1)}</td>
      <td>${run.quality.toFixed(1)}%</td>
      <td>${run.owner}</td>
    </tr>
  `).join("");

  runsTable.querySelectorAll("tr").forEach((row) => {
    const selectRow = () => {
      selectedRunId = row.dataset.runId;
      renderRuns();
      renderInspector();
    };
    row.addEventListener("click", selectRow);
    row.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        selectRow();
      }
    });
  });
}

function renderInspector() {
  const run = runs.find((item) => item.id === selectedRunId) || filteredRuns()[0] || runs[0];
  document.querySelector("#inspector-title").textContent = run.title;
  document.querySelector("#detail-status").textContent = run.status;
  document.querySelector("#detail-guardrail").textContent = run.guardrail;
  document.querySelector("#detail-tokens").textContent = run.tokens;
  document.querySelector("#detail-budget").textContent = run.budget;

  document.querySelector("#signal-list").innerHTML = run.signals.map(([label, value, tone]) => `
    <div class="signal">
      <div class="signal-top">
        <span>${label}</span>
        <span>${value}%</span>
      </div>
      <div class="signal-track">
        <div class="signal-fill ${tone}" style="width: ${value}%"></div>
      </div>
    </div>
  `).join("");
}

function setView(view) {
  const title = viewCopy[view] || viewCopy.overview;
  const isAccounts = view === "accounts";
  const isRunsOnly = view === "runs" || view === "alerts";

  document.querySelector("#view-title").textContent = title;
  document.querySelectorAll(".nav-item").forEach((item) => {
    item.classList.toggle("is-active", item.dataset.view === view);
  });

  headerActions.hidden = isAccounts;
  metricsGrid.hidden = isAccounts || isRunsOnly;
  accountGrid.hidden = !isAccounts;
  dashboardGrid.hidden = isAccounts || isRunsOnly;
  runsPanel.hidden = isAccounts;

  if (view === "alerts") {
    selectedStatus = "incident";
    updateStatusFilter();
  }

  if (view === "models") {
    chartMode = "quality";
    updateChartMode();
  }

  renderRuns();
  renderInspector();
  renderChart();
}

function updateStatusFilter() {
  document.querySelectorAll("[data-status]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.status === selectedStatus);
  });
}

function updateChartMode() {
  document.querySelectorAll("[data-chart]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.chart === chartMode);
  });
}

async function fetchStatusJSON(path, options = {}) {
  let response;
  try {
    response = await fetch(path, {
      cache: "no-store",
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(options.headers || {})
      }
    });
  } catch {
    throw new Error("Start the local connector with `node local-status-server.mjs`, then open http://localhost:8787/.");
  }

  let payload = {};
  try {
    payload = await response.json();
  } catch {
    throw new Error("The local connector returned a non-JSON response.");
  }

  if (!response.ok || payload.ok === false) {
    throw new Error(payload.error || `Status check failed with HTTP ${response.status}.`);
  }

  return payload;
}

function setConnectorNote(id, message, tone = "") {
  const note = document.querySelector(id);
  note.textContent = message;
  note.classList.toggle("ok", tone === "ok");
  note.classList.toggle("error", tone === "error");
}

function setCodexLoading(isLoading) {
  checkCodexButton.disabled = isLoading;
  checkCodexButton.textContent = isLoading ? "Checking..." : "Check Codex";
}

function setOpenRouterLoading(isLoading) {
  checkOpenRouterButton.disabled = isLoading;
  checkOpenRouterButton.textContent = isLoading ? "Checking..." : "Check OpenRouter";
}

function renderCodexStatus(status) {
  document.querySelector("#codex-plan").textContent = humanizePlan(status.planType);
  document.querySelector("#codex-resets").textContent = `${status.resetCredits?.availableCount ?? 0}`;

  const windows = status.windows || [];
  document.querySelector("#codex-windows").innerHTML = windows.length
    ? windows.map((window) => `
      <div class="status-line">
        <div>
          <div class="status-line-title">${escapeHTML(window.title)}</div>
          <div class="connector-note">${formatDuration(window.resetAfterSeconds)} to reset</div>
        </div>
        <div class="status-line-meta">
          <div class="signal-top">
            <span>${formatPercent(window.remainingPercent)} remaining</span>
            <span>${formatPercent(window.usedPercent)} used</span>
          </div>
          <div class="meter-track">
            <div class="meter-fill" style="width: ${Math.max(0, Math.min(100, Number(window.usedPercent) || 0))}%"></div>
          </div>
        </div>
      </div>
    `).join("")
    : `<div class="empty-note">Codex returned no usage windows.</div>`;

  const tone = status.ok ? "ok" : "error";
  const suffix = status.errors?.length ? ` ${status.errors.join(" ")}` : "";
  setConnectorNote("#codex-note", `Checked ${formatCheckedAt(status.checkedAt)}.${suffix}`, tone);
}

function renderOpenRouterStatus(status) {
  document.querySelector("#openrouter-remaining").textContent = formatCredits(status.remainingCredits);
  document.querySelector("#openrouter-used").textContent = `${formatCredits(status.totalUsage)} / ${formatCredits(status.totalCredits)}`;
  setConnectorNote(
    "#openrouter-note",
    `Checked ${formatCheckedAt(status.checkedAt)}. ${formatPercent(status.usagePercent)} of purchased credits used.`,
    "ok"
  );
}

function humanizePlan(value) {
  if (!value) {
    return "Codex";
  }
  return String(value)
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

async function checkCodexStatus() {
  setCodexLoading(true);
  setConnectorNote("#codex-note", "Checking Codex via local connector...");
  try {
    renderCodexStatus(await fetchStatusJSON("/api/status/codex"));
  } catch (error) {
    setConnectorNote("#codex-note", error.message, "error");
  } finally {
    setCodexLoading(false);
  }
}

async function checkOpenRouterStatus() {
  const apiKey = openRouterKeyInput.value.trim();
  if (!apiKey) {
    setConnectorNote("#openrouter-note", "Paste an OpenRouter management API key from your logged-in account.", "error");
    return;
  }

  setOpenRouterLoading(true);
  setConnectorNote("#openrouter-note", "Checking OpenRouter credits via local connector...");
  try {
    renderOpenRouterStatus(await fetchStatusJSON("/api/status/openrouter", {
      method: "POST",
      body: JSON.stringify({ apiKey })
    }));
  } catch (error) {
    setConnectorNote("#openrouter-note", error.message, "error");
  } finally {
    setOpenRouterLoading(false);
  }
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => setView(button.dataset.view));
});

document.querySelectorAll("[data-status]").forEach((button) => {
  button.addEventListener("click", () => {
    selectedStatus = button.dataset.status;
    updateStatusFilter();
    renderRuns();
    renderInspector();
  });
});

document.querySelectorAll("[data-chart]").forEach((button) => {
  button.addEventListener("click", () => {
    chartMode = button.dataset.chart;
    updateChartMode();
    renderChart();
  });
});

rangeSelect.addEventListener("change", () => {
  renderMetrics();
  renderChart();
});

modelSelect.addEventListener("change", () => {
  renderRuns();
  renderInspector();
});

pauseButton.addEventListener("click", () => {
  paused = !paused;
  pauseButton.classList.toggle("is-paused", paused);
  pauseButton.innerHTML = paused
    ? `<span class="button-icon" aria-hidden="true"><svg viewBox="0 0 20 20"><path d="M5.8 4.5 15 10l-9.2 5.5z"></path></svg></span>Resume monitor`
    : `<span class="button-icon" aria-hidden="true"><svg viewBox="0 0 20 20"><path d="M7 4.5v11M13 4.5v11"></path></svg></span>Pause monitor`;
});

checkCodexButton.addEventListener("click", checkCodexStatus);

checkOpenRouterButton.addEventListener("click", checkOpenRouterStatus);

clearOpenRouterKeyButton.addEventListener("click", () => {
  openRouterKeyInput.value = "";
  document.querySelector("#openrouter-remaining").textContent = "Not checked";
  document.querySelector("#openrouter-used").textContent = "-";
  setConnectorNote("#openrouter-note", "Key cleared from this page. It was never stored by Dashis.");
});

renderMetrics();
renderChart();
renderRuns();
renderInspector();
