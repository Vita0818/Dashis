# ARCHITECTURE

## 当前产品边界

Dashis 当前是 macOS 原生 SwiftUI、provider-first 的 AI 用量 dashboard，不使用 `WKWebView`、Web dashboard、Node gateway 或 localhost 业务服务。

- Xcode 工程包含四个 target：macOS App `Dashis`、命令行 helper `ClaudeStatusLineHelper`、XPC service `DashisCollectorWorker`、测试 target `DashisTests`。
- shared scheme `Dashis` 构建 App、helper 与嵌入式 Worker，并在 Test action 运行 `DashisTests`。
- 唯一外层 `NavigationSplitView` 的 Sidebar 使用 macOS 原生 `List(selection:)`、系统 section 与选中态，主 Sidebar 不提供搜索；列表顶部保留 Dashis 已有 28 pt semibold Serif 品牌及原位置，主 Sidebar 固定为 218 pt，再显示 Dashboard、唯一顶层 Settings 入口和当前开启的 provider。Dashboard 通过原生 `ScrollView` 与自适应 `LazyVGrid` 展示同一可见子集的统一系统 `GroupBox` 卡片，provider 路由只打开纯数据主卡；Settings 在外层 detail 内用固定 220 pt 的原生搜索/List 面板承载完整 34-provider catalog、每项原生显示开关、四个 native flow 和其余 30 个 provider 的 41 条 CodexBar live explicit route 配置。Settings 不再创建第二个 split/navigation container，也不提供重复的 Providers 页面或动态 Add provider。
- `script/build_and_run.sh` 是本地 build/run 入口；`.codex/environments/environment.toml` 的 Run action 调用同一脚本。
- `Vendor/CodexBarCore` 与 `Packages/DashisCodexBarCollector` 已接入后台 build graph：App target 只链接 Foundation-only contract，live collector/Core 只链接独立 XPC Worker；Store/UI 通过 exact route、wire v4 和 reverse configuration broker 消费 live observation，再投影为现有 snapshot UI。
- 当前没有 iOS target、远程后端、数据库、长期凭据存储或部署配置；这些边界仍为 `UNKNOWN`。

## 目标分层

```text
DashisApp / DashboardView
  -> display navigation
       Dashboard adaptive visible-provider card grid -> typed ProviderSnapshot priorities
       provider data-only page -> one full typed ProviderSnapshot card
  -> Settings workspace
       second-level complete 34-provider menu + native visibility switches
       native / collector grouped configuration forms
  -> DashisProviderStore
       -> DashisProviderCatalog（34 reviewed entries；4 native / 30 collector）
       persistent non-sensitive hidden-provider IDs / visibleProviders projection
       UI state / session-only inputs / explicit user actions
       route selection / one-run config / consent / generation guards / Clear
       Observation -> Snapshot -> summary/detail projection
  -> DashisProviderService
       composition root only
       -> CodexUsageClient
       -> ClaudeUsageClient
       -> GoogleConsumerUsageClient
       -> GeminiAPIProjectUsageClient
       -> OpenRouterUsageClient
       -> Google ProviderConnectionCoordinator
       -> OpenRouter ProviderConnectionCoordinator
       -> ProviderCollectionRuntime
            -> ProviderRouteRegistry
            -> ProviderRunCoordinator
            -> NativeSnapshotObservationBridge
            -> CollectorOutcomeValidator
            -> CollectorWorkerClient + connection-scoped configuration broker

Shared provider foundation
  -> ProviderSnapshot / QuotaWindow / ProviderBalance / ProviderMetric
  -> ProviderCardProjection / FreshnessPolicy
  -> ProviderJSON
  -> ProviderHTTPClient -> ProviderEndpointPolicy
  -> LoopbackOAuthCoordinator / ProviderOAuthSupport

App target
  -> DashisCollectorContract
       provider/request/outcome/window/freshness/policy DTO
       rollout catalog + 41-route live catalog
       bounded wire v4 + reverse configuration broker
  -> NSXPCConnection
       -> embedded DashisCollectorWorker.xpc
            -> DashisCollectorContract
            -> CodexBarCollector
                 per-operation exact request/planning/single-strategy policy
                 account resolver + upstream context + neutral result/artifact mapper
            -> vendored CodexBarCore v0.45.2
                 63 provider descriptors / strategies / host probes
```

`DashisProviderService` 不解析 provider 响应、不持久化凭据，也不定义 endpoint；它只组装 adapter 和连接协调器。各 adapter 先生成结构化 `ProviderSnapshot`，Store 再统一投影 Dashboard 卡片与详情主卡。两处都直接从 snapshot 生成类型化 `ProviderVisualization` / `ProviderUsageCard`，避免解析旧 key/value 文案或把 UI 文案当成数据模型。

CodexBar 已作为后台 runtime 接到 `DashisProviderService`，但不是现有 Store 的第五个 `ProviderUsageClient`。30 个 collector provider 从 Settings 表单向 Store 提交 exact route 与本次临时配置，runtime 经 XPC Worker 执行单一 strategy，再由不可绕过的 outcome validator 映射为 Dashis-owned `ProviderObservation`，最后投影为现有 `ProviderSnapshot` 并由展示页消费。当前四个 native 设置仍走既有 adapter。`UsageSnapshot`、CodexBar Core 类型和 Core 自有 UI/config 不得渗入 App target、Store 或视图。

`ProviderObservation` 是接线后的 canonical fact model，`ProviderSnapshot` 仍是当前 UI projection。Production route registry 保留四个 native provider 的七条 native route，并追加 `CollectorLiveRouteCatalog` 的 41 条 enabled collector route；Worker 握手报告 `liveRouteCount = 41`。`CollectorRolloutCatalog` 仍登记 34 个 provider、52 条 exact strategy 与 50 条 explicit-source staging binding；live catalog 排除四个 native provider 的重叠路径和三条 automatic-only strategy，只把其余 30 个 provider 的明确 binding 提升为 route。

`DashisProviderCatalog` 把 `CollectorRolloutCatalog.selectedProviderIDs` 投影为 reviewed provider 目录顺序，并从 `CollectorLiveRouteCatalog` 生成每个 collector provider 的 exact methods 与默认 method。它不保存 credential，也不把 automatic-only strategy 宣传为可选来源。Gemini 保留旧 UI/snapshot 导航 ID `google`，但 catalog identity 为 `gemini`，避免重复成 35 个条目。

## 统一 snapshot 语义

`ProviderSnapshot` 包含 provider、scope、source、采集时间、quota windows、balance、metrics、warnings 和 partial failures。来源级别必须保留在模型与无障碍语义中；当真实数据、推导/手动/实验来源或风险需要用户判断时，UI 再显示最短限定词：

| source | 含义 | 当前示例 |
|---|---|---|
| `officialDirect` | 官方接口直接返回值 | OpenRouter key/account 数据、Codex Enterprise Analytics |
| `officialDerived` | 官方 limit 与 usage 经过严格匹配后推导 | Gemini API project quota |
| `officialLocalBridge` | 官方本地程序把字段交给用户命令 | Claude Code `statusLine.rate_limits` |
| `experimentalPrivate` | 非公开、可能失效的只读契约 | Codex personal `wham` |
| `manualOnly` | 没有受支持的第三方机器接口 | Google consumer subscription |

Freshness 由 snapshot 是否有数据、`observedAt` 与 source TTL 共同决定。没有可信数据时只用主值表达 `No data` 类空态，不再重复显示 source/freshness 小字；真实 historical/stale/expired、warning 与 failure 必须显式出现。原始 negative remaining 和超过 100% 的 used 值保留。进度只在服务端 percentage 已知，或 numerator 与正 denominator 均可验证时生成；未知 denominator、limit-only 与普通 KPI 不得退化成 `0%`。只有最终视觉 fraction 被限制在 `0...1`，不能反向覆盖原始数值。

## Provider 数据链路

### Codex

```text
用户点击 Check desktop usage
  -> 安全读取 ~/.codex/auth.json
     regular file / O_NOFOLLOW / current UID / private permissions / <= 1 MiB
  -> GET chatgpt.com/backend-api/wham/usage
     -> plan + credits + optional usage windows
  -> GET chatgpt.com/backend-api/wham/rate-limit-reset-credits
     -> available reset credits（与账户 credits 分开）
  -> experimentalPrivate snapshot；两个请求允许部分成功

用户点击 Check workspace analytics
  -> session-only analytics key + workspace ID
  -> GET api.chatgpt.com/v1/analytics/codex/workspaces/{workspace}/usage
  -> 每页最多 500 条，最多 100 页
  -> officialDirect workspace metrics
```

Personal `wham` 不是公开稳定 API，失败时 fail closed，不能触发登录刷新、额度重置、兑换或其它副作用。decoder 只展示 payload 实际返回的 credits 与窗口：`plan_type` 只作为 scope，`primary_window` / `secondary_window` 只作为槽位；窗口标题按有效 `limit_window_seconds` 生成，缺少 duration 时使用通用标题，不能由槽位名或 plan 名推断 5 小时、周限制或其它周期。`credits.balance`、`credits.unlimited`、`credits.has_credits` 表示账户 credit 状态，`rate-limit-reset-credits` 的 available count 单独显示为 available reset credits。Enterprise Analytics 是组织 workspace 聚合使用量，不等同于个人订阅 remaining。

### Claude

```text
用户点击 Preview connect
  -> 验证 App bundle 中的 helper 与计划安装路径
  -> 安全读取 ~/.claude/settings.json
  -> 生成字段级 statusLine patch 摘要（无持久写入）

用户点击 Apply change
  -> 安装/更新私有目录中的 helper
  -> 再校验 settings fingerprint
  -> 原子写入 statusLine patch

Claude Code 后续调用 statusLine
  -> dashis-claude-statusline 接收原始 stdin
  -> 仅提取 5-hour / 7-day used_percentage 和 resets_at
  -> 原子写入 <= 8 KiB、0600 的净化 snapshot
  -> 若原先已有 statusLine command，将同一份 stdin 传给原命令并转发 stdout/stderr/exit status

用户点击 Reload snapshot
  -> ClaudeUsageClient 安全读取净化 snapshot
  -> officialLocalBridge snapshot
```

helper product `dashis-claude-statusline` 嵌入 `Dashis.app/Contents/MacOS/`。Preview 只验证它并准备指向预定私有路径的 patch；用户确认 Apply 后才安装或更新到 `~/Library/Application Support/com.vitemis.dashis/ClaudeBridge/bin/`，随后原子修改 settings。snapshot 位于同一 `ClaudeBridge` 根下的 `snapshot.json`。

缺少 `rate_limits` 时 helper 不覆盖旧 snapshot；单窗口更新会保留另一窗口；完全相同的窗口不会刷新 `observedAt`。Dashis 不主动发送 Claude 请求，真实更新依赖 Claude Code 后续产生响应。Preview disconnect + Apply 会恢复原 statusLine 并删除安全校验通过的 snapshot；`Clear loaded data` 只清 snapshot，不改变 bridge 配置。

### Google AI

Google provider 有两个互斥 mode，切换 mode 会清除该 provider 当前 mode 的临时状态和展示数据。

Consumer subscription：

- 没有受支持的第三方余额 API；`Open Gemini official page` 只打开官方页面。
- 用户可选填 used/limit/remaining/unit 并记录带采集时间的 manual snapshot。
- 不读取浏览器 Cookie、profile、Keychain、Gemini/Antigravity 私有 token 或 TUI 输出。
- Antigravity 的 quota/credits 由用户在其 CLI 中输入 `/credits` 人工查看，不由 Dashis 抓取。

Gemini API project：

```text
用户输入 Google Desktop OAuth client ID、project ID/number 与可选 exact quota IDs
  -> 默认浏览器打开 accounts.google.com
  -> 随机 127.0.0.1 port + 随机 callback path
  -> PKCE S256 + state + cloud-platform scope
  -> POST oauth2.googleapis.com/token
  -> 仅内存保存短期 access token；丢弃 refresh_token / id_token
  -> GET cloudquotas.googleapis.com/v1/projects/{project}/locations/global/
         services/generativelanguage.googleapis.com/quotaInfos
  -> GET monitoring.googleapis.com/v3/projects/{project}/timeSeries
  -> FULL point 分页按完整 metric/resource labels 合并
  -> 按 quota ID、limit_name、dimension/model/location 和 metric type 严格匹配
  -> minute/hour DELTA 选最新完整可见历史窗并标 exact as-of
  -> concurrent GAUGE 取最新；未知 cadence 不计算 remaining
  -> officialDerived snapshot
```

Project ID/number 由用户手工输入；当前实现不枚举项目。可选 quota ID 取 Cloud Quotas 的 exact `quotaId`，逗号/空白分隔；留空时按受支持 cadence 优先并最多自动选 24 个 definition，防止无界 Monitoring fan-out。授权账户还必须具备 `cloudquotas.quotas.get` 和 `monitoring.timeSeries.list` 所需 IAM 权限。Cloud Monitoring 可能约延迟 150 秒；minute/hour 不能把请求时刻切开的 DELTA 当完整窗口，故选择最新完整公共历史窗并把 as-of 写进 window label 与 warning。RPD 重置按 `America/Los_Angeles` 日历午夜；limit 与 usage 不能可靠对齐、Cloud Quotas 与 Monitoring limit 冲突或 cadence 未知时必须显示 unavailable/警告，不能猜测。

### OpenRouter

OpenRouter 有默认 `Account` mode 与可选 `Single key` mode。产品主目标是整个账户的余额和聚合活动，不要求其它模型调用改用 Dashis 创建的 key。

默认 Account：

```text
用户显式输入 session-only management key
  -> GET /api/v1/credits
     -> total_credits / total_usage / computed remaining
  -> GET /api/v1/activity（不传 api_key_hash/user_id）
     -> 最近 30 个已完成 UTC 日、按 endpoint/model/provider 聚合
  -> GET /api/v1/analytics/meta
  -> POST /api/v1/analytics/query（显式 time range、无默认 filters）
  -> 可选 GET /api/v1/generation?id=...
  -> officialDirect account snapshot

账户 snapshot 成功后，用户显式展开 Recent calls
  -> GET /api/v1/analytics/meta
  -> POST /api/v1/analytics/query
     -> generation_id + 最多一个 api_key_id/model dimension
     -> 显式 1–30 天 time range、hour/day granularity、group_limit 1、limit 20、无 filters
  -> 独立的 metadata-only sidecar state，不写入 ProviderSnapshot
```

Management key 是 OpenRouter 账户管理 credential，本身权限高于普通推理 key，且不能用于模型 completion。Dashis 只在当前 App session 内存中持有它；endpoint allowlist 不包含 `/api/v1/keys` 的 create/update/delete 等管理写接口。`/activity` 返回账户聚合而非逐调用日志。OpenRouter 当前没有原生、带 cursor 的“列出全部 generations”公开 endpoint；Recent calls 只枚举最多 20 条 analytics metadata 行，可能截断或去重，不能声称完整或最新。当前可选 generation 详情仍由用户提供 ID；Dashis 不读取 `/generation/content` 或 prompt/completion。

可选 Single key：

```text
用户切换 Single key 并点击 Connect OpenRouter
  -> 默认浏览器打开 https://openrouter.ai/auth
  -> 随机 127.0.0.1 port + 随机一次性 callback path
  -> PKCE S256（OpenRouter 官方 OAuth 契约没有 state 参数）
  -> POST /api/v1/auth/keys 换取用户控制的 API key
  -> session-only key
  -> GET /api/v1/key
  -> officialDirect key limit / usage / limit_remaining
```

OpenRouter 官方 OAuth 授权 URL 没有定义 `state`，因此实现不伪造 provider 未接受的 state；callback 的隔离依赖高熵随机 path、只绑定 `127.0.0.1`、精确 path 校验、一次性 listener 与 PKCE verifier。Google OAuth 仍使用并严格校验 state。

账户聚合与 analytics：

- analytics 先读取 meta，只选择实际可用且 `is_rate == false` 的可加总 metric/dimension；`metadata.truncated` 时自动缩小时间窗一半重试一次，并明确显示较窄口径或仍不完整警告。
- Recent calls 先读取 meta，再以 `generation_id` 加最多一个 key/model dimension 发起无 filters 的显式时间查询；选择一个 cost/usage metric 和一个 token metric，并显式设置 `group_limit: 1` 与 `limit: 20`，防止 time-series 查询由服务端自动提高总行数。其 loading/error/result 与账户 `ProviderSnapshot` 分离，列表失败不能抹掉余额；`metadata.truncated` 必须直接显示不完整警告。
- 每个子请求保留独立 partial failure，不因一个失败抹掉其它有效结果。
- rate/token metric 分别保留 provider 返回的意义；不得把不同日期、模型或 endpoint 的 rate 相加成一个伪造速率。
- total token 优先 provider 的 `total_tokens`，缺失时使用 prompt + completion；reasoning 只作 output breakdown，不再次相加。

Account Clear 会清除内存中的 management key、输入、snapshot 和 recent-call sidecar。Single-key Clear 还会取消本地 listener/task 并清除 OAuth key/verifier，但无法保证撤销已经由 `/auth/keys` 在 OpenRouter 服务端创建的 key；若授权完成后状态不确定，用户必须在 OpenRouter 官方账户页面撤销该 key。

## CodexBar live 采集接线边界

```text
用户在 Settings 的 collector provider 表单选择 method、填写可选临时配置并点击 Check usage
  -> CollectionTargetKey + routeID + runID + generation
  -> immutable Dashis ProviderRouteRegistry
       拒绝 .auto、未知 route 和不匹配的 source/strategy/pin/manifest/live revision
  -> ProviderRunCoordinator
       同 target supersession / wall-clock result deadline / late-result rejection
  -> CollectorWorkerClient
       <= 256 KiB Data request
       exact route authorization + broker lease + consentGranted
       connection-scoped reverse configuration broker
       只允许 route 声明的键，且最多解析一次
       cancel RPC -> 250 ms grace -> invalidate connection
  -> DashisCollectorWorker.xpc
       single-flight / duplicate request-ID rejection
       Worker-owned exact route authorization
       wire v4 handshake + 34/52/50 staging inventory
       41 live routes + live revision + manifest-set digest
       高风险 route 必须收到本次 consent
       从 reverse broker 解析本次配置
       临时安装 route 允许键；其它继承环境已在启动时清除
       为本 operation 构造 exact single-strategy policy
       deadline -> cancel + collector.shutdown + 2 s grace
                -> Worker process-group kill + _exit fallback
  -> <= 2 MiB Data reply
  -> CollectorOutcomeValidator
       schema / target / source / strategy / attempts / account / time / finite values
  -> ProviderObservation
  -> ProviderObservationSnapshotProjection
  -> ProviderSnapshot
  -> 既有 summary/detail projection

四个 native provider 不经过上述 collector 路径：

native UI action
  -> existing native client / typed NativeProviderObservationExecutor
  -> NativeSnapshotObservationBridge 或既有 ProviderSnapshot 链路

Worker 内部：

已通过 route authorization 的 explicit CollectorRequest
  -> 本 operation 唯一 exact request rule
  -> 本 operation 唯一 planning rule
  -> ambient account 或 host-confirmed selected account context
  -> CodexBar descriptor 生成 strategy list
  -> 本 operation 唯一 exact strategy rule + conservative capability envelope
  -> isAvailable
  -> fetch / provider-specific fallback
  -> returned strategy ID/kind 必须等于 exact-approved strategy
  -> selected account 的 usage identity + dashboard email 必须满足 host expectation
  -> CollectorOutcome schema v2
       raw source + strategy + attempts
       ambient / hostResolved / resultVerified account state
       raw usedPercent / 100-usedPercent（不 clamp）
       window/reset/placeholder/usageKnown
       usage/credits/cost component timestamps
       live provider artifacts / dashboard / sanitized diagnostics
```

上游锁定 CodexBar stable v0.45.2 的实际 commit `91560ca98e776b96fdf910d4a0423c2f0c07a3b9`。Core、SQLite shim 与 Claude watchdog 源码保持原样；Dashis-owned manifest、policy、DTO 和 facade 位于上游目录之外。后续更新必须人工锁新 release，审查 provider enum/descriptor、endpoint、credential path/writeback、subprocess、依赖与许可证，再整体替换。

App target 只链接 `DashisCollectorContract`；`CodexBarCollector` 和 Core 只存在于 Worker target。XPC selector 只传 `Data`，wire v4 日期固定为 Unix 毫秒，budget 为 1–120000 ms，request/response cap 分别为 256 KiB/2 MiB；握手固定 rollout revision、34/52/50 数量、41 条 live route、live revision 与 manifest-set digest。collect 必须携带 exact route/strategy/manifest/upstream-pin/live-revision authorization、一次性 broker lease 和本次 consent。Worker 是故障与生命周期隔离边界，不是完整权限 sandbox；当前 Debug App/Worker 为 ad-hoc 签名。

`CollectorRolloutCatalog` 是 Core-independent 的审计/staging inventory；`CollectorLiveRouteCatalog` 才是当前 production collector route 的唯一来源。live catalog 再维护一份显式冻结的 authorized binding ID 列表，所以新增 staging binding 不会自动上线。App 和 Worker 编译同一份 route identity，握手以 live revision 和 manifest-set digest 证明双方集合一致。每条 live route 固定 provider/source/strategy、route-manifest digest、upstream pin、允许的临时配置键、observed effects、风险摘要与 consent 要求。route digest 绑定执行字段，但 observed effects 仍只是审计线索，不是完整 effect manifest。`opencodego.local`、`kimi.cli`、`mimo.local` 没有 explicit source，只能留在 staging，不能用被禁止的 `.auto` 伪造 exact route。

App Settings 表单的临时配置只存在于 `DashisProviderStore` 内存；每次 collect 建立新 XPC connection 和新 broker lease，只向 Worker 释放所选 route 声明的键，broker 成功解析一次后即消费并移除值。App 启动环境中与当前 route 同名的键也通过这条 lease 释放，页面输入覆盖它。`Clear session data` 会失效当前 generation，并清除该 provider 的 route 输入、observation 和 snapshot。字段留空时，strategy 仍可能使用匹配的本地 provider/CLI/browser 配置。这个 reverse broker 只管理 route 配置值，不是通用 credential、文件、网络或进程代理。

Worker 入口只保留 HOME/PATH/TMPDIR/locale/XDG/XPC、CI/test-safety 等明确 runtime allowlist，并清除其它全部继承环境；每次 collect 把 broker 允许键同时安装到 facade context 与真实 process environment，操作结束后恢复。这样直接读取 `ProcessInfo.processInfo.environment` 或继承环境的子进程也只能看到本 route 的一次性值，而不能看到其它 provider 的 ambient 变量。context 还禁用持久 CLI session，并拒绝 `debugKeepCLISessionsAlive`。Core 仍可通过 HOME 等基础路径访问硬编码 provider 文件、浏览器数据、Keychain service、自己的网络客户端或 credential writeback；login-shell locator 也可能按用户 shell 配置加载环境。因此 exact policy、reverse broker 与 XPC 边界不能描述为完整进程、存储、网络或凭据 sandbox。

strategy kind 不能作为权限边界：pinned Core 的 API/OAuth/Web/CLI strategy 可嵌套其它 probe。当前每次 operation 仍保守使用完整 capability envelope，并另以 exact strategy ID、manifest、pin 和 live revision 限定顶层路径；新 strategy ID 不会命中旧 route。fetch 返回的 strategy ID/kind 还必须与通过 gate 的顶层 strategy 完全一致，否则按 provenance mismatch 终止。这个 gate 不会递归拦截一个已授权顶层 strategy 内部直接调用的其它 adapter，因此顶层 strategy 仍是 opaque 权限单元。风险摘要来自 pinned 源码中观察到的 effects，不代表 runtime 已拦截所有内部副作用；需要 browser session/launch、Keychain、process/subprocess、写回、远程 mutation、潜在计费或可配置 endpoint 的 route 会在 UI 和 Worker 两端要求本次逐次 consent。

host deadline 会发送 cancel RPC、等待 250 ms 后 invalidate XPC connection，防止迟到结果进入当前 generation。Worker 从操作开始同步计时：到期先取消 task 并调用 `collector.shutdown()`，给 Core/CLI 2 秒退出；仍未完成时对 Worker 自有 process group 发出 `SIGKILL` 并 `_exit(124)`，App 后续 XPC 连接会启动新 Worker。这是 operation-scoped hard-stop 兜底，但自行创建新 process group 或脱离 Worker 的后代是否全部终止仍需发布级验证；它不等于完整进程树 sandbox。

## OAuth 与网络安全边界

- OAuth 使用系统默认浏览器，由 `NSWorkspace` 打开 provider 授权 URL；不是 `ASWebAuthenticationSession`。
- loopback listener 只绑定随机 `127.0.0.1` 端口，callback path 含随机 nonce；不绑定 `localhost`、IPv6 或外部接口。
- Google 和 OpenRouter 分别使用独立 `ProviderConnectionCoordinator`；Clear 一个 provider 不应取消另一个 provider 的连接。
- 四个 native provider 的远端数据请求经 Dashis `ProviderHTTPClient`；配置为 ephemeral、无 cache、无 cookie、无 credential store，响应上限 8 MiB。collector Worker 使用 pinned CodexBar Core 自己的网络客户端，不受这条 App allowlist 逐请求代理。
- 远端 redirect 一律拒绝；POST token/code exchange 不重试，只有 GET/HEAD 可对有限的 429/502/503/504 或瞬时网络错误重试一次。
- `ProviderEndpointPolicy` 校验 HTTPS、标准端口、精确 host/path/method/query/body schema，并拒绝 embedded credentials、fragment、trailing slash 与未允许字段。
- 错误只进入净化摘要；不显示 Authorization、key、code、verifier、完整请求/响应或账号标识。

## 状态生命周期

所有远端检查由用户在 Settings 中的显式动作触发；启动 App、浏览 Dashboard 或打开 provider 展示页都不会自动执行 collector。Store 使用每-provider generation 和 operation ID：切换 mode、Clear 或开始新动作后，旧异步响应不能重新写回 UI。collector 临时配置、Google access token、OpenRouter OAuth key/management key、Codex Enterprise analytics key 与 PKCE/OAuth 中间状态只存在于当前 App session。

Claude 是唯一允许事件驱动写入本地净化 snapshot 的 bridge；该文件只含白名单 quota 字段，不是凭据或完整 provider 响应。provider 显示开关是另一类、只含 catalog ID 的非敏感 UserDefaults 偏好，不属于 provider 数据或凭据。当前没有 refresh token 或 API key 的跨启动持久化；未来若引入 Keychain，必须作为独立凭据政策变更评审。

## UI 与设计边界

- Sidebar 列表顶部固定显示不可选择的原有 `Dashis` 品牌标题：28 pt semibold Serif、原 vertical padding 与 `x: 7 / y: 9` 位置；其后固定 `Dashboard`、唯一 `Settings` 入口与当前开启 provider 的展示导航。主 Sidebar 没有搜索。Sidebar 的 min/ideal/max 均为 218 pt，没有重复的 `Providers` 页面或 Add provider。所有普通导航标签允许压缩、保持单行、尾部截断并为 provider 提供 tooltip，选择 provider 进入纯数据展示页。
- Dashboard 按 catalog 稳定顺序显示当前开启 provider 的自适应卡片网格：内容宽时双列、空间不足时单列。每个 provider 只使用一张系统 `GroupBox` 外层展示卡；未检查 collector 明确显示 `Not checked`。整张卡只打开该 provider 的数据展示，不运行检查、连接或配置，也不显示 `Configure` 按钮。全部 provider 关闭时显示指向 Settings 的系统空态。不得伪造余额、窗口、连接状态或指标数。
- Settings 是唯一配置入口和 provider 展示管理入口。进入后，唯一外层 `NavigationSplitView` 的 detail 内使用固定 220 pt、不可折叠的设置面板、被动系统 `Divider` 和可伸缩 grouped `Form`。原生 `NSSearchField` 始终搜索完整 34-provider catalog；下面的系统 `.inset` `List` 每行右侧用原生 switch 控制该 provider 是否出现在主 Sidebar 与 Dashboard，默认全部开启。关闭不删除 provider、snapshot、设置、route、observation 或采集能力，偏好跨启动保留；二级选择只改变右侧 grouped `Form`，不会自动检查。provider 名称必须可压缩、单行尾部截断并提供 tooltip，switch 固定使用系统尺寸；行内不得加入显式水平 spacing、非零最小 `Spacer` 或额外左右 padding。Connection、method、credentials、bridge/OAuth、consent、Check、Clear、Advanced 和 OpenRouter recent-call 查询全部位于这里，provider 展示页不出现设置控件。
- 壳层遵循 macOS 26/27 系统结构：全窗口只有默认样式的一个 `NavigationSplitView` 及其 218 pt `.sidebar` List；Settings detail 内使用原生 `NSSearchField`、220 pt `.inset` List、switch `Toggle`、被动 `Divider` 和 grouped `Form`，没有第二个 split、column visibility 或恢复按钮。`navigationTitle`、Dashboard `ScrollView` / `LazyVGrid` / `GroupBox`、展示页 `ScrollView`、表单、菜单与按钮继续由系统控制。原有 Serif `Dashis` 品牌、位置和稳定的 218 pt 主 Sidebar 是有意保留的品牌/几何例外；不得把 Serif 或手工 offset 扩散到普通导航/正文，也不自绘 Liquid Glass。只有 route/strategy 等代码类内容使用 monospace。若上次顶层选择是 Settings，启动时先回到 Dashboard，避免把配置工作区恢复成主界面初始状态。
- provider 身份在 Sidebar 和 Dashboard 卡头中只以名称表达，不使用 `network`、`cloud`、`terminal`、`globe` 等无法区分真实服务商的泛化图标，也不显示装饰性 chevron。只为 warning、failure 和更多操作保留有明确行为/状态语义的 SF Symbol。
- 有真实数据或风险时只增加一个必要限定词：`Experimental`、`Estimated`、`Manual`、`Historical`、`Stale`、`Expired`、失败/超额或 warning；正常状态不额外占行。
- 每个 provider route 无 snapshot 时，Dashboard 卡与纯展示页的系统主卡都只显示 provider 名称与真实空态；四个 native provider 不改为 CodexBar collector。Dashboard 卡和展示页不附带配置或主操作。Settings provider Form 限制为最大 900 pt、字段最大 420 pt；collector 设置按 `Connection → Credentials（仅有字段时）→ Check Usage → Advanced` 排列。没有字段时不显示重复的 Access section；method footer、凭据生命周期 footer、常驻 consent/risk section 和 Advanced 运行说明均不渲染。高风险 route 的摘要只在点击主操作后的逐次 alert 中出现，consent gate 不变。native provider 仍按各自任务分组，但不再显示常驻解释 footer。exact route/source/strategy 放进单一 `Advanced`，有可清状态时才在 section header 的更多操作菜单提供 `Clear session data`。
- 每个 Settings provider 屏只保留一个当前可执行的主操作。Dashboard 与 provider 详情复用同一 `ProviderVisualizationProjection`：Dashboard 每项是一张紧凑系统 `GroupBox`，详情页则是一张更完整的顶层系统 `GroupBox`。两处最多突出两个同层级主数据 pane：订阅型数据优先选择 5-hour/7-day 等 quota windows；没有窗口但有 balance 时只突出 balance；窗口与 balance 都没有时才选择前两个 metric。Dashboard 卡在双列宽度内横排两个 pane，不承载额外数据；详情卡空间不足时可纵排，窗口存在时的 balance、其余 balance/metric 与 source/scope/observed metadata 放进同一卡片内默认折叠的 disclosure。
- Dashboard 卡内部只保留 provider header、必要限定、label、主要数值/descriptor、系统 `ProgressView` 与必要 reset/status；不显示 metadata 或长 warning body，异常只用必要限定引导用户进入详情。详情主卡再完整呈现 warning、partial failure、额外 usage 与 metadata，但不另套 surface。两处都不嵌套小卡，不使用手绘卡片背景、进度轨道或装饰性阴影。配置、凭据、风险确认和 `Advanced` 只存在于 Settings 的系统 section，绝不与展示卡混排。
- 同一展示屏内不通过 primary、caption、stats、progress 和 raw lines 重复表达同一份 snapshot 数据；类型化 projection 是展示页的唯一数值布局入口，高级配置只留在 Settings 中用户主动展开的 disclosure。
- Codex Analytics 网页的用途仅限于校准 quota/balance 的信息优先级、进度表达与去重；最终交互与壳层仍遵循 macOS 原生组件和平台层级。
- 不删除或重新解释 Sidebar 顶部的原有 `Dashis` 品牌：28 pt Serif、既定位置与 Sidebar 宽度必须保留。品牌本身不附加图标、subtitle、背景或额外装饰，也不把该字体/offset 用到 provider 导航；不恢复 Recent monitors、timeline、旧 Models/Runs/Alerts、首页小指标网格或 inspector-first 布局。

### Debug 视觉 fixture

Debug 构建接受 `--visual-qa` launch argument。它只向 Store 注入一份固定、合成的 Codex snapshot 并将路由切到 Codex 纯展示页；样本包含 5-hour、7-day 两个主窗口与一个次级余额，用于截图、双主指标、进度和折叠层级的视觉回归。fixture 初始化不读取 `~/.codex/auth.json`、其它账户文件、credential 或真实 provider response，也不自动发起网络请求。该路径不属于产品数据源，Release 构建不启用，不能用于证明真实 provider correctness。

## 未确认架构

- iOS target、跨 Apple 平台共享代码与移动端 OAuth/Claude bridge：`UNKNOWN`。
- 后端/BFF、数据库、通知、定时刷新、长期历史与 dashboard 业务 KPI：`UNKNOWN`。
- OpenRouter/Google refresh token 是否可持久化到 Keychain：未批准；当前明确不持久化。
- Google consumer 若未来发布官方第三方余额 API、Codex personal 若未来发布公开 quota API：需要重新研究和安全评审，不能自动沿用当前 manual/private 路径。
- 非 App Store 分发方向已确定；正式产物需使用同一 Developer ID 为 App、XPC Worker 与辅助 executable 签名并完成 notarization。当前 ad-hoc Debug 签名不代表 release 配置已经完成。
