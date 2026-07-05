# CURRENT_STATE

## 当前状态

- 项目名：Dashis。
- 目标方向：AI dashboard。
- 当前目录：`/Users/vita/Vitemis/Dashis`。
- 当前 Git root：`/Users/vita/Vitemis/Dashis`。
- 当前远程：`origin` -> `https://github.com/Vita0818/Dashis.git`。
- 当前源码：已建立 v0.1 无依赖静态 Web 原型，入口为 `index.html`，样式为 `styles.css`，交互和 mock 数据为 `app.js`。
- 当前本地连接器：`local-status-server.mjs` 使用 Node 内置模块提供静态页面和只读状态接口。
- 当前 Xcode 项目：`Dashis.xcodeproj` 已包含可构建的 macOS App target `Dashis` 和 shared scheme `Dashis`。

## 已有能力

- 已建立 Vitemis Agent 入口规范。
- 已建立 Codex、Claude、Gemini 的权限边界。
- 已建立项目 docs 基线和临时下一目标文件。
- 已初始化独立 Git 仓库，并连接远程 `https://github.com/Vita0818/Dashis.git`。
- 已建立可直接打开的 Dashis v0.1 AI 监测仪表盘原型：
  - 左侧导航：Overview、Models、Accounts、Runs、Alerts。
  - 主面板：Latency、Cost、Quality、Incidents 指标卡。
  - Accounts 面板：可通过本地连接器查看 Codex 使用窗口、Codex reset credits 和 OpenRouter credits。
  - 图表区：吞吐柱形 + latency/quality 折线切换。
  - 运行区：Runs 表格、状态过滤、模型过滤、时间范围切换。
  - 右侧 inspector：选中 run 的状态、guardrail、tokens、error budget 和信号条。
  - 主题：light mode 使用 macOS 系统白；dark mode 使用 macOS 系统黑，跟随 `prefers-color-scheme`。
- 已从只读审阅的 `codex-reset` 迁入 Codex 状态查询思路：
  - 用户给出的路径 `/Users/vita/ThridParty/codex-reset` 不存在；实际只读检查路径为 `/Users/vita/ThirdParty/codex-reset`。
  - Dashis 仅在本地连接器运行时读取 `~/.codex/auth.json`，不会在前端展示或写入 token。
  - Codex 外呼限制为 `https://chatgpt.com/backend-api/wham/usage` 和 `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`。
  - OpenRouter 外呼限制为 `https://openrouter.ai/api/v1/credits`，需要用户从已登录账号提供 management API key；该 key 只用于本次本地请求，不进入 localStorage 或项目文件。
- 已加入 Node 内置测试 `tests/status-logic.test.mjs`，覆盖 endpoint allowlist、JWT account fallback、Codex usage/reset credits 归一化和 OpenRouter credits 归一化。
- 已加入 `Dashis.xcodeproj` macOS App target：
  - SwiftUI 入口位于 `App/macOS/DashisApp.swift`。
  - `App/macOS/DashboardView.swift` 提供 macOS 原生 `NavigationSplitView` 工作台根视图。
  - `App/macOS/DashisDesign.swift` 定义 Dashis 原生主题 token：light mode 为 macOS 系统白，dark mode 为 macOS 系统黑，状态色仅用于 ok/warn/incident。
  - `App/macOS/DashisModels.swift` 提供当前原生 UI mock 数据模型。
  - `App/macOS/DashisSidebar.swift`、`DashisDashboardDetail.swift`、`DashisDashboardComponents.swift`、`DashisInspector.swift` 构成 sidebar / content / inspector dashboard。
  - 原生 macOS UI 已按 Intatis 的克制工作台方式收敛：title-only header、原生 source-list sidebar、无品牌装饰图标、无说明性 subtitle、无 Recent monitors、无 timeline 辅助叙事面板。
  - 静态 Web 原型已同步收敛为同类信息架构：Dashis 标题、核心导航、指标、账户状态、图表、Runs 表和 inspector；不再显示 Settings、timeline、品牌图标、页面 subtitle、metric footnote 或操作提示语。
  - macOS App 已移除 WebKit bridge，不再把 `index.html`、`styles.css`、`app.js` 复制进 app bundle；Web 原型仍保留为独立入口。
  - 当前先实现 macOS target；iOS target 尚未创建。

## 未确认

- Web 原型是否继续作为长期入口，或逐步迁移到原生 SwiftUI UI，仍未最终确认。
- iOS target 的具体形态、共享代码边界和是否复用 WebKit 容器仍未确认。
- macOS App 中账号状态查询是否改为原生 bridge、连接本地 HTTP 连接器，或保留 mock 状态仍未确认。
- dashboard 真实用户角色、数据源、指标定义、权限模型和刷新策略。
- 是否需要 OpenAI API、数据库、内部服务或第三方 API；当前只确认 Codex/OpenRouter 账号状态的只读查询。
- 是否需要真实后端、持久化、本地 mock 数据文件或 fixture。

## 工作区注意

- Vitemis 根仓库已有其他未提交改动；不得清理、回退或覆盖。
- Dashis 当前只应改动 Dashis 项目内文件，除非用户明确要求跨项目改动。
- Dashis 是嵌套 Git 仓库；提交请求默认只作用于 Dashis 当前 Git root，不包含 Vitemis 父仓库或其它子仓库。
- v0.1 dashboard 业务数据仍为 `app.js` 中的示例 mock。
- 只有用户显式启动 `node local-status-server.mjs` 并点击账户状态按钮时，Dashis 才会读取本机 Codex auth 或向 OpenRouter credits endpoint 发起只读查询。
