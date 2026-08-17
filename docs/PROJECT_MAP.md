# PROJECT_MAP

## 当前目录

```text
Dashis/
├── AGENTS.md / CLAUDE.md / GEMINI.md
├── .codex/environments/environment.toml
├── App/macOS/
│   ├── DashisApp.swift
│   ├── DashboardView.swift
│   ├── DashisSidebar.swift
│   ├── DashisDashboardDetail.swift
│   ├── DashisDashboardComponents.swift
│   ├── DashisDesign.swift
│   ├── DashisModels.swift
│   ├── DashisProviderCatalog.swift
│   ├── DashisProviderStore.swift
│   ├── DashisProviderService.swift
│   ├── ProviderSnapshot.swift
│   ├── ProviderUsageClient.swift
│   ├── ProviderCardProjection.swift
│   ├── ProviderJSON.swift
│   ├── ProviderEndpointPolicy.swift
│   ├── ProviderHTTPClient.swift
│   ├── LoopbackOAuthCoordinator.swift
│   ├── ProviderConnectionCoordinator.swift
│   ├── ProviderOAuthSupport.swift
│   ├── CodexUsageClient.swift
│   ├── ClaudeStatusLineCodec.swift
│   ├── ClaudeUsageClient.swift
│   ├── ClaudeSettingsPatcher.swift
│   ├── GoogleQuotaClient.swift
│   ├── OpenRouterUsageClient.swift
│   └── ProviderIntegration/
│       ├── CollectionTarget.swift
│       ├── ProviderObservation.swift
│       ├── ProviderRouteRegistry.swift
│       ├── ProviderRunCoordinator.swift
│       ├── NativeSnapshotObservationBridge.swift
│       ├── CollectorOutcomeValidator.swift
│       ├── CollectorWorkerClient.swift
│       └── ProviderCollectionRuntime.swift
├── Tools/
│   ├── ClaudeStatusLineHelper/main.swift
│   └── DashisCollectorWorker/
│       ├── main.swift
│       ├── Info.plist
│       ├── CollectorWorkerListener.swift
│       ├── CollectorWorkerCoordinator.swift
│       └── DashisCollectorWorkerService.swift
├── tests/DashisTests/
│   ├── ProviderFoundationTests.swift
│   ├── ProviderDecoderTests.swift
│   ├── ProviderCorrectnessTests.swift
│   ├── SecurityBoundaryTests.swift
│   └── ProviderIntegrationTests.swift
├── Vendor/CodexBarCore/
│   ├── Package.swift / Package.resolved
│   ├── UPSTREAM.md / PATCHES.md
│   ├── LICENSE / LICENSES/ / THIRD_PARTY_NOTICES.md
│   └── Sources/
│       ├── CodexBarCore/             # v0.45.2 原样采集 Core
│       ├── CSQLite3/
│       └── CodexBarClaudeWatchdog/
├── Packages/DashisCodexBarCollector/
│   ├── Package.swift / Package.resolved
│   ├── README.md / CAPABILITIES.md
│   ├── Sources/
│   │   ├── DashisCollectorContract/ # DTO + rollout/live catalogs + wire v4 + reverse broker
│   │   └── CodexBarCollector/
│   └── Tests/CodexBarCollectorTests/
├── Dashis.xcodeproj/
│   ├── project.pbxproj
│   ├── project.xcworkspace/xcshareddata/swiftpm/Package.resolved
│   └── xcshareddata/xcschemes/Dashis.xcscheme
├── script/build_and_run.sh
├── codex-report/07_10_26-21_34-provider-quota-integration.md
├── codex-report/07_26_26-15_09-codexbar-unified-wiring.md
├── codex-report/07_30_26-13_24-codexbar-selected-provider-rollout.md
└── docs/
    ├── ARCHITECTURE.md
    ├── CURRENT_STATE.md
    ├── DO_NOT_BREAK.md
    ├── PROJECT_MAP.md
    ├── TESTING.md
    └── USER_TUTORIAL.md
```

## 入口与 targets

- Agent 入口：根目录 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md`；`docs/` 中同名文件为 shim。
- macOS App：`Dashis.xcodeproj` / target 与 shared scheme `Dashis` / `App/macOS/DashisApp.swift`。
- Claude helper：target `ClaudeStatusLineHelper`，源码为 `Tools/ClaudeStatusLineHelper/main.swift` 与共享 codec，product 名 `dashis-claude-statusline`。
- Collector Worker：target `DashisCollectorWorker`，product 为嵌入式 XPC service；App target 只链接 `DashisCollectorContract`，Worker target 链接 `DashisCollectorContract` 与 `CodexBarCollector`。
- Swift tests：target `DashisTests`；由 shared scheme `Dashis` 的 Test action 执行。
- SwiftPM tests：`Packages/DashisCodexBarCollector` 仍可独立运行；package products同时被 App/Worker target 按边界引用，但 package test suite 不是 shared scheme Test action 的一部分。
- build/run：`script/build_and_run.sh`；Codex app Run action 位于 `.codex/environments/environment.toml`。
- Bundle ID：`Dashis` 为 `com.Vita0818.DashisMac`，Worker/XPC service 为 `com.Vita0818.DashisMac.CollectorWorker`，`DashisTests` 为 `com.Vita0818.DashisMacTests`；命令行 helper 不设置 bundle ID。

## UI 与状态层

- `DashboardView.swift`：唯一 `NavigationSplitView` 根视图和 root-owned Store；不强制 split style，并通过 `DashisWindowLayout.primarySidebarWidth` 把主 Sidebar 的 min/ideal/max 同时锁为 218 pt。持久化顶层 Dashboard / Settings / provider 展示选择；旧 `providers` 选择仅作为兼容 alias 回到 Dashboard，若跨启动恢复到 Settings 或已隐藏 provider 则安全回到 Dashboard。
- `DashisSidebar.swift`：原生 `.sidebar` `List(selection:)` + `Section`，主 Sidebar 不含搜索；列表第一行保留原有 28 pt semibold Serif `Dashis`、vertical padding 与 `x: 7 / y: 9` 位置，其后展示 `Dashboard`、唯一 `Settings` 入口与当前开启的 provider。主 List 使用新的稳定 identity，避免沿用已删除嵌套 split 的视图恢复状态；所有普通导航标签都显式使用 `minWidth: 0 / maxWidth: infinity`、单行尾部截断。provider 导航继续由系统负责行高、强调色、选择和纵向滚动，没有泛化 provider 图标、手绘描边选中态、独立 `Providers` 页面或动态 Add/custom provider。
- `DashisDashboardDetail.swift`：用系统 `navigationTitle` 和 Dashboard `ScrollView` / 自适应 `LazyVGrid` 按 catalog 稳定顺序展示当前开启 provider 的卡片；宽窗口双列、窄窗口单列，整张卡与 Sidebar provider 都只导航到纯数据展示页，不执行检查；全部隐藏时显示指向 Settings 的系统空态。顶层 `Settings` 不再创建任何 navigation/split container，而是在唯一外层 detail 内用零间距 `HStack` 组合固定 220 pt 设置面板、被动系统 `Divider` 与可伸缩详情：面板顶部是原生 `NSSearchField`，下方 `.inset` `List` 始终显示完整 34-provider catalog 和 trailing system switch；右侧是所选 provider 的真实 grouped Form，二级 provider 选择通过独立 `SceneStorage` 保留。名称可压缩、单行尾部截断并提供 tooltip，switch 固定为系统尺寸；该面板没有 column visibility、split divider 或 toolbar toggle。
- `DashisDashboardComponents.swift`：无 provider 图标/按钮的统一 Dashboard `GroupBox` 展示卡；卡内复用 `ProviderVisualizationProjection`，最多显示两个同层主数据 pane，订阅窗口优先、无窗口时余额优先，无 snapshot 时只显示诚实空态。最大 900 pt 的纯数据 provider `ScrollView` 只包含一张更完整的系统 `GroupBox` 主卡；最大 900 pt 的 Settings grouped `Form` 独立承载所有配置。额外 usage、metadata、warning/failure 只留在详情主卡内且不再嵌套小卡。collector 设置只保留 Connection、按需 Credentials、主操作与 Advanced；无字段时不显示 Access，method/credential footer、常驻 consent 卡和 Advanced 说明均已删除，逐次风险只在 action-time alert 出现。Codex/Claude/Gemini/OpenRouter 的常驻解释 footer 与 Recent Calls 引导文案同样删除，字段、真实状态、错误、操作和确认仍保留。
- `DashisDesign.swift`：`DashisWindowLayout` 集中保存 960 × 640 最小窗口、1160 × 760 默认窗口、218 pt 主 Sidebar 和 220 pt Settings Sidebar；同文件保留 Dashis 原有品牌专用 Serif font helper 和品牌主文字色，同时让正文、表单、导航与状态继续使用系统字体/semantic colors。Dashboard 卡与 provider 详情主卡直接使用系统 `GroupBox`，这里不定义自绘页面背景、卡片描边/阴影或假 Liquid Glass。只有 route/strategy 等代码类信息使用 monospace。
- `DashisModels.swift`：provider-first UI 值类型、`.native` / `.collector` integration 边界与四个现有 native provider 空态；源码中的 custom factory 仅是内部 fallback，当前 UI 不暴露注册入口。
- `DashisProviderCatalog.swift`：把 Foundation-only `CollectorRolloutCatalog.selectedProviderIDs` 投影为稳定的 34 个 UI 条目；`gemini` 显式映射到原 `google` 导航 ID，30 个 collector provider 由 `CollectorLiveRouteCatalog` 暴露 exact methods 与默认 method，automatic-only strategy 不进入前台列表。
- `DashisProviderStore.swift`：按前台 catalog 发布完整 34-provider 目录，并从持久化的隐藏 ID 集合投影 `visibleProviders` 给主 Sidebar 与 Dashboard；新/既有 provider 默认开启，关闭只写入非敏感 UserDefaults 偏好，不清除 snapshot、配置、route 或 observation。Store 继续为 Dashboard/展示页提供 snapshot/loading 状态，为 Settings 中的 collector provider 保存内存态 route selection、临时配置与 observation，并在用户点击 `Check usage` 时构造 exact command 调用 runtime。`clearCollectorSession` 才会失效 generation，并清除该 provider 的 route 输入、observation 与 snapshot。
- `DashisProviderService.swift`：adapter composition root；除既有 native clients/connection coordinators 外，持有无启动 I/O 的 `ProviderCollectionRuntime`，供 Store 的显式 collector check 调用。

## 统一 provider 基座

- `ProviderSnapshot.swift`：provider ID/scope/source、quota window、balance、metric、warning/failure、freshness。
- `ProviderUsageClient.swift`：adapter protocol。
- `ProviderCardProjection.swift`：snapshot 到 provider summary 与类型化 `ProviderVisualization`/`ProviderUsageCard` detail 的统一投影；区分 remaining/used 进度、去重重复 balance/window、保留负 remaining，且 denominator/percentage 未知时不生成进度。
- `ProviderJSON.swift`：有限数值、日期和安全错误归一化。
- `ProviderEndpointPolicy.swift`：request method/URL/query/body allowlist；OpenRouter generation analytics 额外限制 ID、dimensions、granularity、窗口和 limit，并拒绝 `/generation/content`。
- `ProviderHTTPClient.swift`：ephemeral/no-cache/no-cookie `URLSession`、redirect 拒绝、有限 retry。
- `LoopbackOAuthCoordinator.swift`：由默认浏览器发起授权，只绑定随机 `127.0.0.1` callback、校验授权 URL/path 与适用 provider 的 state、支持取消。
- `ProviderConnectionCoordinator.swift`：OpenRouter 与 Google 各自独立的 session OAuth orchestration；OpenRouter 官方 flow 无 state，使用随机 callback path + PKCE，Google 使用 state + PKCE。
- `ProviderOAuthSupport.swift`：Google Desktop OAuth/PKCE/state/token request 与 session access token。

## Provider adapters

- `CodexUsageClient.swift`：personal experimental `wham` 与 Enterprise Analytics 分页。
- `OpenRouterUsageClient.swift`：账户级 management credits、无单-key过滤的聚合 activity、meta-driven analytics/可选 generation、最多 20 条 metadata-only recent-call sidecar，以及次要的 OAuth single-key limit。
- `GoogleQuotaClient.swift`：consumer manual snapshot、Cloud Quotas/Monitoring decoder 与 quota derivation。
- `ClaudeStatusLineCodec.swift`：Claude statusLine 净化 DTO、安全 snapshot 文件与 prior command marker。
- `ClaudeUsageClient.swift`：本地 snapshot 到 5-hour/7-day quota windows。
- `ClaudeSettingsPatcher.swift`：helper 安装、settings 顶层 byte-range Connect/Disconnect patch 与并发保护。
- `Tools/ClaudeStatusLineHelper/main.swift`：statusLine stdin capture、净化快照更新、prior command 兼容转发。

## 后台采集 integration

- `CollectionTarget.swift`：以 product + selected UUID/ambient slot + scope 构成稳定 target identity，并携带 run ID/generation。
- `ProviderObservation.swift`：Dashis-owned canonical fact model，分离 engine、source trust、account evidence、strategy/attempt provenance、components、diagnostics 与 artifacts。
- `ProviderRouteRegistry.swift`：不可变 fail-closed 路由表；保留四个 native provider 的七条 native route，并从 live catalog 追加 41 条 enabled collector route；release 拒绝 `.auto`、未知 route 与缺失或不匹配的 pin/manifest/revision。
- `ProviderRunCoordinator.swift`：按 `CollectionTargetKey` 管理 generation/run，取消同 target 的旧任务，执行真实 wall-clock result deadline，并拒绝迟到/错 identity 结果。
- `NativeSnapshotObservationBridge.swift`：将当前 native `ProviderSnapshot` 薄包装为 observation，保留 raw 超额值；四个 native provider 仍沿用现有调用链。
- `CollectorOutcomeValidator.swift`：只有 schema、target、source、strategy、attempt、account verification、时间、有限数值与 payload cap 全部通过的 outcome 才能映射为 observation。
- `CollectorWorkerClient.swift`：Data-only `NSXPCConnection` transport，per-request connection、wall-clock result deadline、cancel RPC、grace 后 invalidate；collect connection 同时导出 connection-scoped reverse configuration broker，只向绑定的 request/route/lease 解析一次 exact route 声明的配置键。
- `ProviderCollectionRuntime.swift`：生产 route/worker/coordinator composition；初始化不做 I/O。collector command 生成 exact route authorization、一次性 broker lease 与本次 consent，验证 Worker outcome 后映射为 `ProviderObservation`；Store 再经 `ProviderObservationSnapshotProjection` 生成 `ProviderSnapshot`。
- `Tools/DashisCollectorWorker/`：单任务 XPC Worker，提供 handshake、63-provider catalog、cancel 与 collect；握手报告共用 rollout revision、34/52/50 staging 数量、41 条 live route、live revision 与 manifest-set digest。Worker 复核 exact authorization、通过 reverse broker 取回本次配置，并为该 operation 创建只含一个 request/planning/strategy rule 的 collector policy。

## CodexBar engine 与 contract

- `Vendor/CodexBarCore/Sources/CodexBarCore/`：CodexBar v0.45.2、commit `91560ca...` 的完整 63-provider 采集与调度闭包；474 个 Swift 文件保持原样。
- `Vendor/CodexBarCore/Sources/CSQLite3/`：Linux Core 所需 SQLite module map/shim。
- `Vendor/CodexBarCore/Sources/CodexBarClaudeWatchdog/`：可独立构建的可选 Claude CLI process-tree watchdog；当前没有嵌入 App。
- `Vendor/CodexBarCore/UPSTREAM.md` / `PATCHES.md`：上游 SHA、tree hash、刷新流程与零 patch 声明。
- `Packages/DashisCodexBarCollector/Sources/DashisCollectorContract/`：不 import Core 的 provider/request/outcome/window/freshness/policy/artifact DTO，以及 App/Worker 共用的 rollout catalog、live route catalog、wire v4 与 reverse broker contract。
- `CollectorRolloutCatalog.swift`：34 个用户选定 provider、52 条 pinned exact strategy、50 条 explicit-source binding、3 条 automatic-only 阻断项和源码审计中已观察到的风险；它是审计/staging inventory，不自动授权执行。
- `CollectorLiveRouteCatalog.swift`：用显式冻结的 authorized binding ID 列表排除 Codex、Claude、Gemini、OpenRouter 的 native 重叠路径，为其余 30 个 provider 固定 41 条 live explicit route；记录 exact strategy/source、route-manifest digest、upstream pin、配置字段名、observed effects、风险摘要和逐次 consent 要求。route digest 不是完整 effect manifest。
- `CollectorHostBroker.swift`：一次性配置 request/reply codec；限制为 64 KiB、最多 32 项、单值 16 KiB，并只接受规范化的环境变量式键名。
- `CollectorWireEnvelope.swift` / `CollectorWireCodec.swift` / `CollectorXPCProtocol.swift`：wire v4 Data-only XPC envelope、256 KiB request/2 MiB response cap、Unix 毫秒日期、1–120000 ms budget、`.auto` source 拒绝、live catalog/manifest-set 握手一致性、exact route authorization，以及 connection-scoped reverse configuration broker protocol。
- `Packages/DashisCodexBarCollector/Sources/CodexBarCollector/`：account context 构造、request/planning/exact-strategy 默认拒绝 gate、strategy provenance 校验、selected-account result identity/dashboard 验证，以及 result/live-artifact 映射。
- `Packages/DashisCodexBarCollector/CAPABILITIES.md`：接入前逐 strategy endpoint、凭据、写回、subprocess、潜在费用与 ToS 审查要求。
- `Dashis.xcodeproj/project.pbxproj` 通过 `XCLocalSwiftPackageReference` 接入 facade package。App target 不链接 `CodexBarCollector`/Core；只有 Worker target 链接 live engine，并由 App 的 XPC copy phase嵌入。

## 测试与研究

- `ProviderFoundationTests.swift`：endpoint allowlist（含 OpenRouter generation analytics/content 拒绝）、source/freshness、负余额投影、ISO 日期、PKCE。
- `ProviderDecoderTests.swift`：Codex/OpenRouter decoder（含 recent-call 去重、截断与冲突拒绝）、Claude codec/settings patch、Google manual/quota/OAuth fixture，以及手工数值推导的有限值边界。
- `ProviderCorrectnessTests.swift`：34-provider 前台 catalog、4 native/30 collector integration、provider 可见偏好的默认值/隐藏/恢复/跨 Store 持久化及 Settings 完整 catalog 不变、41 条 route 与 collector 内部 action metadata 边界、严格 decoder、Google cadence/dimension/limit/concurrent/OAuth correctness；UI 不再把该 metadata 渲染成 `Configure` 按钮。
- `SecurityBoundaryTests.swift`：JSON bridge、endpoint path/query、OpenRouter account/recent-call request shape 与 sidecar isolation、Claude snapshot 文件属性与 embedded helper 端到端边界。
- `ProviderIntegrationTests.swift`：target identity、41-route registry、`.auto`/未知 route 拒绝、native/collector raw mapping、合成 live route、Observation→Snapshot、unknown-credit、supersession、deadline/cancellation、native interaction/account binding，以及嵌入式 XPC wire-v4 handshake/catalog。
- `Packages/DashisCodexBarCollector/Tests/`：63-provider Core catalog、34/52/50 rollout inventory、41 条 live route、automatic-only 阻断、逐次 consent 风险、planning/strategy deny-before-probe、provenance、fallback/cancellation、account identity、schema v2、wire v4 bounds/handshake、broker codec、live artifacts/dashboard/ownership、未知 credit、raw over-quota、placeholder/usageKnown 与保守 freshness；全部为离线合成测试。
- `codex-report/07_10_26-21_34-provider-quota-integration.md`：本轮四 provider 研究、来源分级、实施路线与实现附录。
- `codex-report/07_26_26-15_09-codexbar-unified-wiring.md`：非 App Store 分发前提下的统一 target、XPC、领域模型、路由、迁移和 release gate。
- `codex-report/07_30_26-13_24-codexbar-selected-provider-rollout.md`：34-provider 最终 staging 范围、前台 4 native/30 collector 投影、52 strategy/50 binding 清单、automatic-only 异常、风险与启用边界。
- 自动测试必须保持合成、离线且不读取真实 `~/.codex`、`~/.claude`、浏览器、Keychain 或用户 provider 数据。

## 生成物

- 仓库内无 build 生成物。脚本与验证命令把 DerivedData 写入系统临时目录。
- `Dashis.app` 内嵌 helper 位于 `Contents/MacOS/dashis-claude-statusline`；`Preview connect` 不复制文件，只有用户确认 `Apply change` 才会复制到 `~/Library/Application Support/com.vitemis.dashis/ClaudeBridge/bin/`。
- `Dashis.app` 内嵌 Collector Worker 位于 `Contents/XPCServices/DashisCollectorWorker.xpc`；启动 App、Dashboard 或 provider 展示页不会自动发起 XPC collect，只有用户在 `Settings` 的 30 个 collector provider 设置中点击 `Check usage` 才会执行匹配的 41 条 live route 之一。
- Claude 净化 snapshot 位于同一 app-support 根下的 `snapshot.json`，不属于 Git 生成物，Clear/Disconnect 可删除。
- 当前两个本地 SwiftPM package 均参与 Xcode dependency resolution；Contract 进入 App/Worker，Core 只进入 Worker。仍没有 Web bundle、Node 依赖或远程部署配置。
