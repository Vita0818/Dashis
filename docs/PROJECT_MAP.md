# PROJECT_MAP

## 当前目录

```text
Dashis/
├── AGENTS.md
├── App/
│   └── macOS/
│       ├── DashboardView.swift
│       ├── DashisDashboardComponents.swift
│       ├── DashisDashboardDetail.swift
│       ├── DashisDesign.swift
│       ├── DashisInspector.swift
│       ├── DashisModels.swift
│       ├── DashisSidebar.swift
│       └── DashisApp.swift
├── CLAUDE.md
├── Dashis.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/
│       └── xcschemes/
│           └── Dashis.xcscheme
├── GEMINI.md
├── app.js
├── index.html
├── local-status-server.mjs
├── styles.css
├── tests/
│   └── status-logic.test.mjs
└── docs/
    ├── AGENTS.md
    ├── CLAUDE.md
    ├── GEMINI.md
    ├── ARCHITECTURE.md
    ├── CURRENT_STATE.md
    ├── DO_NOT_BREAK.md
    ├── NEXT_TARGET.md
    ├── PROJECT_MAP.md
    └── TESTING.md
```

## 入口

- Codex：`AGENTS.md`
- Claude：`CLAUDE.md`
- Gemini：`GEMINI.md`
- docs shim：`docs/AGENTS.md`、`docs/CLAUDE.md`、`docs/GEMINI.md`
- Dashboard v0.1：`index.html`
- 本地状态连接器：`local-status-server.mjs`
- 状态逻辑测试：`tests/status-logic.test.mjs`
- Xcode macOS App：`Dashis.xcodeproj` / scheme `Dashis`

## 源码与配置

- `index.html`：静态 Web 入口和 dashboard DOM 结构。
- `styles.css`：macOS white/black 主题、布局、组件样式和响应式规则。
- `app.js`：mock telemetry、runs、过滤、图表、inspector、pause/resume 交互，以及 Codex/OpenRouter 状态面板的前端请求和渲染。
- `local-status-server.mjs`：Node 内置模块实现的本地 HTTP 服务，提供静态文件、`/api/status/codex` 和 `/api/status/openrouter`。
- `tests/status-logic.test.mjs`：Node 内置 `node:test` 测试，验证状态查询 allowlist 与响应归一化。
- `App/macOS/DashisApp.swift`：macOS SwiftUI app 入口。
- `App/macOS/DashboardView.swift`：macOS app 的原生 SwiftUI 根视图，使用 sidebar / dashboard content / inspector 工作台布局。
- `App/macOS/DashisDesign.swift`：Dashis 原生设计 token、白/黑主题、玻璃卡片 modifier 和 page header。
- `App/macOS/DashisModels.swift`：当前原生 dashboard mock 数据和值类型。
- `App/macOS/DashisSidebar.swift`：原生 sidebar 和导航项，保留 title-only 品牌文本。
- `App/macOS/DashisDashboardDetail.swift`：主 dashboard 内容、header controls、metrics、accounts 表、chart 和 runs 表。
- `App/macOS/DashisDashboardComponents.swift`：metric card 和 custom SwiftUI chart 组件。
- `App/macOS/DashisInspector.swift`：右侧 inspector，展示选中 run 的字段、signals 和 pause/resume 动作。
- `Dashis.xcodeproj/project.pbxproj`：Xcode project，包含 macOS App target `Dashis`。
- `Dashis.xcodeproj/xcshareddata/xcschemes/Dashis.xcscheme`：shared scheme，用于 Xcode 和 `xcodebuild` 构建 `Dashis`。
- 当前没有包管理器配置、额外构建脚本或部署配置。

## 生成物

当前无仓库内生成物。`Dashis.xcodeproj` 是手写项目配置，不是派生生成物。`xcodebuild` 产物写入 Xcode DerivedData，不在当前 Git root 内。未来生成物目录应写入本文件，并在 `.gitignore` 或项目约束中明确处理。
