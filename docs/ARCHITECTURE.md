# ARCHITECTURE

## 当前事实

Dashis 当前已有 v0.1 无依赖静态 Web 原型：

- `index.html` 提供应用外壳、导航、指标、图表、Runs 表格和右侧 inspector 结构。
- `styles.css` 提供 macOS 风格的系统白/黑主题、玻璃感面板、紧凑仪表盘布局和响应式适配。
- `app.js` 提供本地 mock telemetry、run 数据、过滤、图表渲染、选中态、视图切换和 pause/resume 交互。
- `local-status-server.mjs` 提供本地 HTTP 连接器，负责读取 Codex Desktop 本机登录状态并调用 Codex/OpenRouter 只读状态接口。
- `tests/status-logic.test.mjs` 覆盖状态连接器的 endpoint allowlist、token account fallback 和响应归一化逻辑。
- `Dashis.xcodeproj` 当前包含 macOS App target `Dashis` 和 shared scheme `Dashis`。
- `App/macOS` 是当前 Apple 平台源码入口；macOS App 已改为原生 SwiftUI dashboard，不再使用 `WKWebView` 承载 Web 页面。
- iOS target 仍未创建；项目方向已明确为 macOS + iOS，但本轮只落地 macOS target。

v0.1 业务 dashboard 不连接真实 API、数据库、OpenAI、内部服务或业务凭据。所有业务指标数据均为本地示例 mock。账户状态查询是独立的本地只读连接器能力，只有在用户启动本地服务并点击检查按钮后才触发。

## 计划方向

Dashis 是 AI dashboard 项目。未来可能包含：

- dashboard UI：展示模型、任务、使用量、质量、成本、状态或其他业务指标。
- 数据层：本地 mock、文件、API、数据库或内部服务。
- AI 集成：OpenAI API、其他模型供应商或本地推理服务。
- 权限与凭据：API key、service token、OAuth、cookie 或内部凭据都不得写入仓库。

## 未确认架构

- 前端框架：当前为无依赖静态 Web；是否升级到 React/Vite、SwiftUI、Next.js 或其他框架仍为 UNKNOWN。
- 后端或 BFF：UNKNOWN。
- 数据存储：当前只有内存 mock；真实存储为 UNKNOWN。
- 部署方式：UNKNOWN。
- 认证授权：UNKNOWN。
- 指标定义：v0.1 示例包含 latency、cost、quality、incidents、tokens、guardrail、error budget；真实业务定义仍为 UNKNOWN。

## v0.1 前端分层

```text
index.html
  app shell / semantic structure / controls
styles.css
  design tokens / layout / components / light-dark system colors
app.js
  mock data / state / render functions / event handlers / status panel client
local-status-server.mjs
  static file server / local status API / strict remote endpoint allowlists
tests/status-logic.test.mjs
  status API unit tests with Node test runner
Dashis.xcodeproj
  macOS App target / shared scheme / bundled dashboard resources
App/macOS
  SwiftUI app entry / native dashboard root / design tokens / models / sidebar / panels / inspector
```

## macOS target

```text
Dashis.app
  SwiftUI WindowGroup
    -> DashboardView
      -> NavigationSplitView
        -> DashisSidebar
        -> DashisDashboardDetail
        -> DashisInspector
```

- macOS App UI 当前全部由 SwiftUI 实现：sidebar、内容画布、指标卡、账户状态表、图表、runs 表和右侧 inspector。
- 设计语言继承 Intatis 的工作台结构、serif title、紧凑玻璃卡片、sidebar/content/inspector 信息架构；主题色不继承 Intatis，Dashis light mode 以 macOS 系统白为主，dark mode 以 macOS 系统黑为主。
- 原生 UI 采用 Intatis 的去装饰化方式：页面 header 只保留标题，sidebar 使用原生 source-list 行，不展示品牌图标、说明 subtitle、Recent monitors、timeline 或操作提示语。
- 静态 Web 原型同步采用去装饰化 dashboard 结构，不再展示 Settings、timeline、页面 subtitle、metric footnote 或重复提示语。
- 当前 macOS App 不启动 Node 本地连接器，也不读取任何凭据；账号状态卡仍是 mock/status placeholder，长期原生查询方案待确认。
- Web dashboard 业务数据仍为 `app.js` mock；原生 macOS dashboard 目前使用 `DashisModels.swift` 中的 mock 数据。

## v0.1 状态连接器

```text
Browser UI
  -> GET /api/status/codex
       local-status-server.mjs
         -> read ~/.codex/auth.json
         -> GET https://chatgpt.com/backend-api/wham/usage
         -> GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits

Browser UI
  -> POST /api/status/openrouter { apiKey }
       local-status-server.mjs
         -> GET https://openrouter.ai/api/v1/credits
```

- Codex 状态逻辑参考只读审阅的 `/Users/vita/ThirdParty/codex-reset`：从 `~/.codex/auth.json` 读取 `tokens.access_token`，优先从 JWT payload 的 `https://api.openai.com/auth.chatgpt_account_id` 取 account id，失败时 fallback 到 `tokens.account_id`。
- Codex 请求头包含 `Authorization: Bearer <access_token>`、`originator: Codex Desktop`、`OAI-Product-Sku: CODEX`、`Accept: application/json`，有 account id 时加 `ChatGPT-Account-Id`。
- Codex endpoint allowlist 只允许 `https://chatgpt.com/backend-api/wham/usage` 和 `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`，拒绝 query、fragment、非 HTTPS、子域、非标准 path 和 trailing slash。
- OpenRouter endpoint allowlist 只允许 `https://openrouter.ai/api/v1/credits`。官方文档要求 Bearer API key，并标注该 credits endpoint 需要 management key。
- 连接器返回给前端的是归一化后的状态摘要，不返回 token、API key 或完整远端响应。
- 本地服务监听 `127.0.0.1`，不面向局域网暴露。

## 设计边界

- 继承 Intatis 的工作台结构语言：窄侧边栏、内容画布、右侧 inspector、紧凑指标卡、表格和状态面板。
- 不继承 Intatis 主题色；Dashis light mode 背景为 `#ffffff`，dark mode 背景为 `#000000`。
- 语义色仅用于状态：ok、warning、incident 和 macOS system blue 选择态；不得发展为彩色主题。
- UI 必须是实际 dashboard，不做营销 landing page。
- UI 不应重新引入装饰性品牌块、辅助说明文案、无数据作用的提示语或重复叙事面板。
- Dashis 已开始建立 Apple 平台项目；当前只确认 macOS 原生 SwiftUI target，iOS target 仍待后续实现。

## 设计原则

- 先确认 dashboard 的核心用户、指标和数据源，再选择技术栈。
- 涉及真实凭据、账号、私有数据或内部服务时，必须使用安全替代方案。
- 账户状态连接器必须保持只读、显式触发、严格 allowlist、无凭据持久化。
- 文档中的架构描述必须跟随实际代码更新；完成的持久性改动要及时回写。
