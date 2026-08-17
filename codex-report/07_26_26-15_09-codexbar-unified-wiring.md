# Dashis × CodexBar 最终统一接线方案

> **历史状态，已被当前实现取代（2026-07-30）：** 本文保留当时的 wire-v3 / live-route-0 决策过程，不再代表当前源码。当前实现为 wire v4、30 个 collector provider、41 条 live explicit route、one-run broker 和已开放的 `Check usage`；以 `docs/CURRENT_STATE.md`、`docs/ARCHITECTURE.md` 与源码为准。

## MODEL_CHECK_RESULT

OpenAI Codex（GPT-5 系列；当前运行时未提供更精确的公开版本号）。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Dashis`
- Git root：`/Users/vita/Vitemis/Dashis`
- 路径与预期项目根目录一致。
- 开始本任务时已存在 `docs/` 修改以及未跟踪的 `Packages/`、`Vendor/`；本报告不覆盖、回退或整理这些已有改动。

## FILES_WRITTEN

- `App/macOS/DashisProviderService.swift`
- `App/macOS/ProviderIntegration/`
- `Tools/DashisCollectorWorker/`
- `Packages/DashisCodexBarCollector/`
- `Vendor/CodexBarCore/UPSTREAM.md`
- `Dashis.xcodeproj/project.pbxproj`
- `Dashis.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `tests/DashisTests/ProviderIntegrationTests.swift`
- `docs/CURRENT_STATE.md`
- `docs/PROJECT_MAP.md`
- `docs/ARCHITECTURE.md`
- `docs/DO_NOT_BREAK.md`
- `docs/TESTING.md`
- `docs/USER_TUTORIAL.md`
- `codex-report/07_26_26-15_09-codexbar-unified-wiring.md`

## DECISION_STATUS

本文是 Dashis 接入 CodexBar 采集引擎的最终统一技术路线。

本文最初只确认方案；用户在 2026-07-28 明确授权“后台接好、前端先不要改”，随后在 2026-07-30 进一步授权前台开放。当前实施边界是：允许把 reviewed 34-provider identity/source 元数据投影到 Sidebar、Dashboard 与只读详情；仍不允许因此启用任何真实 CodexBar provider route。

本文采用以下确定前提：

1. Dashis 永远不进入 Mac App Store。
2. 产品通过非 App Store 方式分发，可使用 Developer ID 签名、公证、Hardened Runtime、独立 XPC service、受控辅助进程与 provider CLI。
3. 不需要为了 App Store 审核或 App Sandbox 能力表而削弱采集功能。
4. “不进 App Store”不等于取消安全边界。仍然不使用 root、setuid 或常驻特权 helper；网络、凭据、本地文件、浏览器、Keychain、子进程和潜在费用继续由 Dashis 明确授权和审计。
5. `Vendor/CodexBarCore` 保持固定 upstream commit 的字节一致性，不直接打本地补丁。

## IMPLEMENTATION_STATUS_2026_07_28

已完成：

- App target 只链接 `DashisCollectorContract`。
- 新增并嵌入 `DashisCollectorWorker.xpc`；只有 Worker 链接 `CodexBarCollector`/Core。
- 新增 wire v3 的 bounded Data-only XPC contract、canonical `ProviderObservation`、route registry、run coordinator、native bridge 与 outcome validator/mapper；握手会核对 App/Worker 共用 rollout catalog revision。
- production runtime 已接入七条既有 native adapter 的类型化 executor，并在执行前校验 interaction、selected-account credential UUID 与 project/workspace scope。
- collect request 必须携带 exact route/strategy/manifest/upstream-pin authorization；Worker 会用自己的 registry 二次核验。
- production registry 只启用既有 native route；CodexBar route 已登记但全部 disabled。
- Worker 可完成 handshake、报告 34-provider / 52-strategy / 50-binding staging catalog、返回 63-provider Core catalog，并对 collect default-deny。
- 此阶段完成时 Dashboard、Sidebar、provider detail、控件和 `DashisProviderStore` 未修改；后续前台开放见 `IMPLEMENTATION_STATUS_2026_07_30`。

仍是启用任一 live route 前的 release gate：

- 逐 strategy effect manifest 与 host HTTP/Credential/LocalState/Keychain/Browser/Subprocess broker。
- operation-scoped Worker/PID/签名验证和进程树 TERM/KILL escalation；当前只有 cancel RPC、短 grace 与 XPC invalidation。
- live `ProviderObservation`→UI projection、账户设置映射与逐 provider canary。
- Developer ID、Hardened Runtime、notarization 和 App/Worker/辅助 executable 的同身份 release 签名。

## IMPLEMENTATION_STATUS_2026_07_30

用户已把后续 rollout 范围收敛为 34 个 provider。Foundation-only contract 新增 `CollectorRolloutCatalog`，锁定 pinned CodexBar 中 52 条 exact strategy 与 50 条非 `.auto` source binding，并记录源码审计中已观察到的副作用。App 与 Worker 通过 wire v3 握手核对同一 revision 和 34/52/50 数量，App 还会把每条 binding 与 Worker 返回的 63-provider Core catalog 交叉校验。

这不是 live enablement：Worker authorization registry 仍为空，`liveRouteCount = 0`。`opencodego.local`、`kimi.cli`、`mimo.local` 只在上游 `.auto` planner 中可达，因此当前没有 exact binding；Azure OpenAI、Ollama API、Doubao API 与 AWS Bedrock 被显式标记为潜在费用风险。

随后完成 34-provider 前台 catalog：四个现有 native flow 继续可操作，Gemini 显式复用内部 `google` 导航/数据流；其余 30 个入口只展示由 explicit binding 推导的 prepared source，并由 Store integration gate 保证无采集 action。启动或浏览这些入口不调用 runtime/XPC，Worker live registry 仍为 0。

## EXECUTIVE_DECISION

最终架构固定为：

> 一个 Dashis 编排器、两类采集引擎、一个 Dashis 领域事实模型、一个 UI 投影。

具体含义：

- Dashis Native Engine 继续承载已经更强、更安全或 CodexBar 不具备的原生实现。
- CodexBar Engine 承载其余 provider 的成熟采集 planner、strategy、fallback 语义与解析逻辑。
- `CollectorOutcome` 只作为 CodexBar 的防腐层结果 envelope。
- 新增 `ProviderObservation`，作为 Dashis 唯一内部事实模型。
- `ProviderSnapshot` 保留，但降为 UI projection，不再承担多账户、多来源、fallback、完整 provenance 或组件级 freshness。
- CodexBar Core 不直接注册为第五个 `ProviderUsageClient`，也不直接进入现有 Store。

## TARGET_TOPOLOGY

```text
用户刷新 / 后台调度
  -> CollectionTarget
       productID + accountUUID/ambientSlot + scopeID
  -> Dashis Route Registry
       固定 engine
       固定 requested source
       固定 exact strategy
       固定 effect manifest
       固定 fallback 条件
  -> ProviderRunCoordinator
       runID
       target generation
       wall-clock result deadline
       cancellation
       interaction authorization
  -> NativeEngine
       -> Native result mapper
  或
  -> signed DashisCollectorWorker.xpc
       -> CodexBarCollector
       -> pinned CodexBarCore
       -> CollectorOutcome
  -> Dashis Outcome Validator
       schema / target / strategy / provenance
       account / identity / timestamp / artifact
  -> ProviderObservation
  -> ObservationReconciler
  -> ProviderSnapshot / typed sidecars
  -> DashisProviderStore
  -> Dashboard / provider detail
```

## NON_APP_STORE_DISTRIBUTION_DECISION

### 采用 XPC Collector Worker

CodexBar live runtime 放入一个随 Dashis 一起签名和公证的 `DashisCollectorWorker.xpc`。

主 App：

- 只依赖 Foundation-only `DashisCollectorContract` 和 Dashis 自己的领域模型。
- 不 import `CodexBarCore`、CodexBar UI/config 类型或 provider-specific live 类型。
- 通过 `NSXPCConnection` 发送版本化执行请求并接收 `CollectorOutcome`。
- 负责 route、账户、用户授权、generation、deadline、最终写回和 UI。

Worker：

- 链接 `CodexBarCollector` 与 pinned `CodexBarCore`。
- 不提供 localhost HTTP server，不监听 LAN，不依赖外部已安装的 CodexBar App/CLI。
- 不通过 shell 启动命令。
- 只执行单个已授权 target 的单次任务；完成后可退出，由系统按需重新拉起。
- 卡死、超时或取消时，当前主 App 会发送 cancel RPC、等待短 grace 并终止 XPC connection；可验证地终止 Worker 和已启动进程树仍是 live-route release gate。
- 只返回中立的 Codable outcome，不返回 Core 对象或原始 HTTP/HTML/body。

### 为什么仍要独立进程

即使不进 App Store，独立 Worker 仍然有价值：

- CodexBar/Core/CLI/Web probe 卡死不会阻塞 App 主状态机。
- 可以实施整个操作的硬 deadline，而不是只依赖 Swift cooperative cancellation。
- 可以在上游升级时保持 App 与 UI 的 ABI/类型边界稳定。
- 可以限制日志、输出大小、临时文件和生命周期。
- 可以让 worker 崩溃与 App Store/generation 状态隔离。
- 可以对 worker 的签名、Team ID、bundle version 和 upstream pin 做启动前校验。

Worker 是故障和生命周期隔离边界，不应被描述成自动获得的完整安全沙箱。

### 非 App Store 不改变的安全要求

- 使用 Developer ID 签名与 notarization。
- 开启 Hardened Runtime。
- Worker 与辅助 executable 必须随 App 固定嵌入，不从 `$PATH` 或任意用户路径发现。
- 启动前校验 bundle 内固定相对路径、签名、Team ID 与版本。
- 不把 token、Cookie、OAuth code、verifier 或账号 ID放进进程参数。
- 不使用 root、Authorization Services 提权、LaunchDaemon、setuid 或长期驻留的特权 helper。
- 本地文件、Keychain、浏览器 profile 和 CLI 访问仍需 exact manifest 与用户授权。

## MODULE_BOUNDARIES

### 1. DashisCollectorContract

现有 contract 继续作为 App 与 Worker 的稳定传输边界：

- `CollectorRequest`
- `CollectorOutcome`
- source、strategy、attempt、account resolution
- component freshness
- diagnostics、credential ownership
- versioned provider artifacts

它不得依赖 `CodexBarCore`。

### 2. CodexBarCollector

继续负责：

- request gate
- planning gate
- exact strategy gate
- context construction
- selected-account result verification
- upstream result/artifact 映射
- strategy provenance 校验

它不负责最终 Dashis source classification、UI、Store、跨 provider merge 或产品 scope 判断。

### 3. ProviderIntegration

新增 Dashis-owned integration layer，负责：

- `CollectionTarget`
- `CollectionTargetKey`
- `ProviderProductID`
- `ProviderAccountID`
- `ProviderObservation`
- `ProviderRoute`
- `ProviderRouteRegistry`
- `StrategyEffectManifest`
- `ExecutionPermit`
- `ProviderRunCoordinator`
- `CollectorOutcomeValidator`
- `CollectorOutcomeMapper`
- `ObservationReconciler`
- `ProviderSnapshotProjection`

### 4. Existing native adapters

现有 native adapter 不直接重写。先通过薄 wrapper 将结果转为 `ProviderObservation`。

后续只有当某个实现明确退休时，才删除其重复运行路径。迁移期允许 canary 对比，但正式运行时不允许两个实现竞争“谁先返回就用谁”。

### 5. ProviderSnapshot

`ProviderSnapshot` 继续作为当前 Dashboard/detail 的展示输入：

- quota windows
- balance
- metrics
- warnings
- partial failures
- UI source/scope

它不再是采集层事实模型，也不保存原始 fallback attempts、完整账户证据或所有 provider artifact。

## CANONICAL_TARGET_IDENTITY

当前 `[ProviderID: ProviderSnapshot]` 不能承载正式接线后的数据。

统一 key 固定为：

```text
CollectionTargetKey =
  ProviderProductID
  + ProviderAccountSlot
  + ProviderScopeID
```

其中：

```text
ProviderAccountSlot =
  selected(Dashis-owned stable UUID)
  或
  ambient(provider-specific isolated slot)
```

`ProviderID` 只负责品牌分组，不再代表唯一数据槽位。

建议的 product ID：

```text
codex.personal
codex.enterprise
claude.local
claude.oauth
claude.admin
claude.web
google.consumer.manual
gemini.project
gemini.cli
vertex.project
openrouter.account
openrouter.key
```

其余 CodexBar provider 也必须分配稳定的 Dashis product ID。Product ID 描述产品/数据口径，不能使用“当前由哪个 engine 实现”作为 ID。

## PROVIDER_OBSERVATION

`ProviderObservation` 是 Dashis 唯一内部事实模型，至少必须表达：

```text
target key
run ID / generation
engine: native | codexBar
requested source
resolved source
exact strategy ID / kind
complete attempts
Dashis source trust classification
account resolution / identity proof
quota observations
balance observations
metric observations
cost observations
component timestamps
confidence
diagnostics / failures
typed provider artifacts
collectedAt / finishedAt
```

每个 quota、balance、metric 和 cost component 都必须拥有自己的：

- semantic ID
- scope/dimensions
- value/unit
- `observedAt`
- confidence
- provenance

来源可信度与采集引擎是两个正交字段：

```text
engine = native | codexBar
sourceKind =
  officialDirect
  officialDerived
  officialLocalBridge
  experimentalPrivate
  manualOnly
```

CodexBar 返回的 source 字符串不能直接决定 Dashis sourceKind。最终分类由 pinned `(provider product, exact strategy)` manifest 给出。

UI 可以在折叠 metadata 中显示 `Via CodexBar`，但不能因为使用 CodexBar 就把 private endpoint 标成 Official，也不能把官方 API 无故降级成 Experimental。

## ACCOUNT_MODEL

### Selected account

- 账户选择只认 Dashis 分配的稳定 UUID。
- label/email 只用于显示，不能选择 credential。
- credential handle 在执行前绑定到 UUID。
- account-specific environment/settings 必须完整替换 ambient context，不允许合并。
- identity expectation 至少需要规范化 email 或 provider account ID 作为稳定 anchor。
- fetch 后 usage identity 与同包 dashboard identity 必须一致。
- 只有 `.resultVerified` 的 selected-account payload 才可发布。
- identity mismatch、证据不足或多来源冲突时整包拒绝，并停止 fallback。

### Ambient account

- 只允许用于本来就属于“当前本机 ambient identity”的来源，例如 Claude local bridge 或用户显式选择的本地 CLI/auth-file source。
- ambient 结果进入独立 ambient slot。
- ambient 结果不得自动归因给某个已保存账户。
- 没有稳定身份的 Claude local bridge 不得静默合并到 Claude OAuth selected account。

## ROUTE_REGISTRY

`ProviderRouteRegistry` 是 Dashis 的唯一执行路由来源。

每条 route 固定：

```text
route ID
provider product
account mode
scope
engine
requested source
exact strategy ID / kind
interaction class
includeCredits
includeOptionalUsage
effect manifest digest
source classification
fallback successor
fallback error classes
UI visibility
enabled state
minimum supported upstream pin
```

Release 不允许：

- 宽泛 `.auto` 授权整条上游 pipeline。
- 按 strategy kind 推断真实权限。
- 新 strategy ID 自动继承旧 allow rule。
- 从 upstream provider catalog 自动生成 enabled routes。
- custom policy 在 Release 中无条件返回 allow。

upstream pin、strategy ID、manifest digest、endpoint 或副作用改变后，对应 route 自动回到 disabled。

## EXACT_EFFECT_MANIFEST

每个 planner 和 exact strategy 必须有版本化 effect manifest，并分别描述 `resolveStrategies`、`isAvailable` 和 `fetch` 三阶段。

Manifest key 至少包含：

```text
upstream commit
provider
requested source
runtime
strategy ID + kind
includeCredits
includeOptionalUsage
interaction
ambient / selected account mode
```

Manifest 必须声明：

### Network

- scheme、host、port
- method、path template
- query/body/header schema
- redirect policy
- retry policy
- response cap
- official/private/inferred endpoint 分类

### Credential and local state

- environment key
- config/auth file
- Keychain service/account
- browser profile/domain
- SQLite/XML/JSON/JSONL/log path
- symlink、owner、mode、size 与 file type 约束

### Mutation

- OAuth refresh
- provider credential file writeback
- Keychain write
- Cookie/cache write
- local config write
- remote account/resource mutation

### Subprocess

- fixed executable
- fixed argument template
- cwd
- minimal environment
- stdin/stdout/stderr limits
- timeout
- process-group termination

### Interaction and cost

- 是否可能弹 Keychain/browser/system prompt
- 是否打开默认浏览器
- 是否要求人工确认
- 是否可能产生 usage、费用或创建远端资源
- 对应的用户提示与 source label

## EXECUTION_PERMIT

现有 `CollectorPolicyDecision.allowed` 继续作为 facade gate，但不能成为 Release 的最终权限凭证。

每次执行由 Dashis Manifest Gate 签发短时 `ExecutionPermit`，绑定：

```text
run ID
target key
generation
account UUID / ambient slot
credential handle
provider
exact strategy
effect manifest digest
interaction authorization
absolute monotonic deadline
allowed effects
```

每个 broker 操作都必须重新验证 permit。

fallback 到下一个 strategy 时必须重新取得新的 exact permit，不能继承前一个 strategy 的权限。

## HOST_SERVICES_AND_BROKERS

最终 live strategy 不能继续任意使用 Core 自己的：

- `URLSession`
- `ProcessInfo.processInfo.environment`
- `FileManager` HOME 扫描
- Keychain API
- browser profile reader
- `Process`
- `curl` fallback
- provider credential writer

需要向 Core/strategy 注入 Dashis host services：

```text
HTTPBroker
CredentialBroker
LocalStateBroker
KeychainBroker
BrowserBroker
SubprocessBroker
Clock / Deadline
```

Broker 继续保留 Dashis 当前安全语义：

- ephemeral HTTP
- no cache / no cookie / no URL credential store
- exact endpoint/method/query/body allowlist
- redirect deny
- 默认 8 MiB response cap，manifest 可进一步收紧
- 只有幂等 GET/HEAD 有有限 retry
- POST/token exchange 不自动 retry
- 净化错误，不返回 secret/header/body/account ID
- 固定 executable，无 shell
- bounded pipe、deadline、process-group kill

当前 pinned Core 还没有完整 host-services 注入能力。这是正式启用 live CodexBar strategy 前的硬门槛。

实施方式优先级固定为：

1. 先向 CodexBar upstream 提交通用 host-services 注入改造。
2. 合并并发布后，整体升级 Dashis pin。
3. 在新 pin 上建立 exact manifest 与离线回归。

如果上游未接受，则策略保持 disabled；不得为了赶进度直接修改 `Vendor/CodexBarCore` 或放宽 Dashis 全局网络/凭据边界。

## CREDENTIAL_LIFECYCLE

- 采集默认只读。
- secret 由 Dashis credential broker 以 opaque handle 提供，不能塞进宽泛 environment dictionary。
- OAuth refresh 的新 token 先保留在 operation memory。
- 只有 outcome 通过 target、strategy、identity、generation 和 deadline 校验后，host 才能事务式提交 writeback。
- cancel、timeout、account mismatch、identity mismatch 或迟到结果一律放弃 writeback。
- 创建 credential、扩大 OAuth scope、修改 provider auth 文件或远端账户状态必须是独立用户操作，不能伪装成 Refresh。
- potentially billable probe 只能由显式用户操作授权。
- browser Cookie store 与 provider auth 文件默认不由 collection refresh 修改。
- 当前 facade callback 不能作为最终事务写回边界，因为 callback 可能早于最终 identity/generation 校验。

## INTERACTION_POLICY

`userInitiated` 必须由真实 UI event 产生一次性 authorization，不能由 adapter 自报。

后台任务默认只允许：

- 无弹窗
- 无浏览器 profile 读取
- 无可能触发 UI 的 Keychain 查询
- 无 credential/local/remote mutation
- 无 potentially billable probe
- 已明确绑定的 selected account
- 已通过 exact manifest 的只读 route

以下操作只能由用户显式触发：

- browser/Cookie source
- Keychain prompt
- CLI login
- private Web API
- OAuth scope 扩大
- credential writeback
- potentially billable probe
- 创建或修改远端资源

## DEADLINE_AND_CANCELLATION

默认 operation budget：

- background：30 秒
- user action：60 秒
- manifest 可缩短
- 绝对上限：120 秒

fallback 只能使用同一个 operation 的剩余预算，不能重新计时。

取消必须同时：

- cancel URLSession task
- 关闭 browser operation
- 关闭 XPC request/pipe
- 终止整个 subprocess process group
- 先 TERM，经过短 grace 后 KILL
- 清理有界临时资源
- 禁止 persistent CLI session 和 detached orphan
- worker 不响应时终止 XPC worker

Clear、切换账户、切换 mode 或启动新刷新后：

- target generation 递增
- 旧结果不得发布
- 旧 credential update 不得提交
- 旧 artifact 不得恢复

## FALLBACK_POLICY

外层 fallback 由 Dashis Route Registry 决定。

允许 fallback：

- exact strategy unavailable。
- manifest 明确列出的可修复认证状态。
- 下一 route 仍属于相同 product、account 与 scope。
- 下一 route 不扩大用户已同意的 effect 集合。

禁止 fallback：

- policy denied
- account/identity rejected
- provenance mismatch
- cancellation
- deadline
- decoder/schema/contract failure
- rate limit
- 临时网络错误
- provider server error
- 已取得部分有效结果
- 从 API/OAuth 静默升级到 Web Cookie、浏览器、Keychain、CLI 或 potentially billable probe

“补充更多字段”属于 enrichment，不属于 fallback。Enrichment 必须产生独立 observation。

## RECONCILIATION_AND_FRESHNESS

### 不允许的合并

- 不同 product 不合并。
- 不同 account 不合并。
- 不同 scope 不合并。
- 相同外观但语义不同的百分比不合并。
- 不平均、不累加同一 quota percentage。
- 不使用“最后返回者胜出”。
- 不用较新的 credits/cost 时间给旧 usage 续命。

### 同一 semantic measurement

只有稳定的：

```text
product
account
scope
metric/window ID
dimensions
unit
```

全部一致时，两个 observation 才可能竞争同一个 semantic measurement。

Winner 按 route manifest 固定优先级、账户证据、confidence 和 freshness 选择。未获胜 observation 只保留为 provenance/diagnostic，不参与计算。

### Freshness

- usage、credits、cost、每个 quota window 分别保存时间。
- 每张 UI 卡片按其实际展示组件计算 freshness。
- provider 总体状态取当前主要展示组件中最差的 freshness。
- optional artifact 不参与总体 freshness。
- 在 UI 还没有组件级时间前，过渡期只能一个 observation 投影一个 snapshot，禁止混合多个不同时间来源。

## FINAL_PROVIDER_ROUTES

| Product target | 最终 engine / route | 决定 |
| --- | --- | --- |
| `codex.personal` | 加固后的 CodexBar `codex.oauth`；只有可修复认证失败才到 `codex.cli` | 长期采用 CodexBar 采集逻辑；Web 只能显式选择 |
| `codex.enterprise` | Dashis native | CodexBar 没有同等 workspace analytics，永久保留 native |
| `claude.local` | Dashis status-line bridge | 默认、低副作用来源 |
| `claude.oauth` | CodexBar exact OAuth strategy | 独立 selected-account route，用户显式启用 |
| `claude.admin` | CodexBar exact Admin API strategy | 独立 organization scope |
| `claude.web` | CodexBar exact Web strategy | Experimental，仅用户显式动作，不进后台 fallback |
| `google.consumer.manual` | Dashis native/manual | 保持人工读数 |
| `gemini.project` | Dashis native | Google Cloud project quota 的权威实现 |
| `gemini.cli` | CodexBar `gemini.api` | 独立 Experimental 产品；不能映射成 API-key 或 project quota |
| `vertex.project` | disabled | 当前 CodexBar mapper 没有公开可展示 quota，修复前不接 |
| `openrouter.account` | Dashis native | 保留 management-account scope、analytics 与安全边界 |
| `openrouter.key` | Dashis native | 保留普通 key scope 与 OAuth PKCE |
| CodexBar `openrouter.api` | disabled | 避免 account/key 混合与能力倒退 |
| 其余非重叠 provider | CodexBar exact strategy | 默认 disabled；effect manifest 与 host broker 完成后逐条启用 |

## CODEX_PERSONAL_MIGRATION

Codex Personal 不永久保留两套随机竞争的正式实现。

迁移过程：

1. 保留当前 Dashis Personal 作为生产默认和安全基线。
2. 加固 CodexBar `codex.oauth`，完成 host transport、只读默认、身份、credits、额外窗口与 deadline。
3. 使用完全合成 fixture 验证 parser、窗口、credits、reset credits、identity、partial failure 与 freshness。
4. 增加用户显式触发的 canary 对照；不自动后台双跑，不把真实 body 写入日志。
5. 达到语义等价后，正式 route 切换到加固后的 CodexBar。
6. `codex.cli` 只处理 manifest 列出的可修复认证状态。
7. 当前 native Personal 从正式运行路由退休；其安全文件读取、endpoint 和数值边界继续保留为 broker/test 能力。

Codex Enterprise 不参与该迁移。

## CLAUDE_COMPOSITION

- `claude.local` 继续默认使用 Dashis status-line bridge。
- `claude.oauth`、`claude.admin` 和 `claude.web` 是不同 target/scope，不是 local bridge 的自动 fallback。
- 用户启用 OAuth 后，local bridge 仍可单独存在，但没有稳定同账户证据时不得自动 merge。
- Admin API 的组织成本/token 数据不得覆盖个人 subscription quota。
- Web Cookie route 始终标为 Experimental。
- 后台不能从 local bridge 静默升级到 Keychain、CLI 或 browser Cookie。

## GOOGLE_AND_GEMINI_SPLIT

必须维持四个独立产品语义：

```text
google.consumer.manual
gemini.project
gemini.cli
vertex.project
```

- `gemini.project` 使用 Dashis 官方 Cloud Quotas + Monitoring 推导。
- `gemini.cli` 表示 Gemini CLI / Code Assist entitlement。
- CodexBar `gemini.api` 的名字不能被 UI 或 policy 解释成普通 Gemini API key。
- `gemini.cli` 当前 private endpoint、ambient OAuth file、credential mutation 和 possible subprocess 必须全部进入 manifest。
- `vertex.project` 在 mapper 输出完整 quota 前保持 disabled。
- 四者的数字永不合并、平均或互相 fallback。

## OPENROUTER_DECISION

OpenRouter 正式路线只保留 Dashis native：

- account 与 single key 明确分开。
- management key 与普通 key 权限分开。
- account credits/activity/analytics/recent calls 继续保留。
- endpoint 固定、redirect 拒绝、response cap 和 session-only credential 继续保留。
- CodexBar `openrouter.api` 不参加正式 route 或 fallback。

只允许选择性借鉴 CodexBar 的状态建模或测试思路，不迁移其 mixed account/key snapshot、任意 HTTPS base URL 或钳制后的结果。

## UI_SCOPE

采集层支持 63 个 provider，不代表 UI 展示全部 upstream provider。前台只展示用户选定且经过 Dashis presentation review 的 34 个。

当前阶段：

- Sidebar 和 Dashboard 按 `CollectorRolloutCatalog.selectedProviderIDs` 展示 reviewed 34-provider catalog。
- Codex、Claude、Gemini、OpenRouter 保持现有 native 动作；另外 30 个条目只读、无采集 action。
- 不恢复动态 Add provider。
- 不改变当前 Dashboard 扁平摘要和 provider detail 视觉结构。
- 新的 account/product/scope 模型继续在后台领域层落地；前台可见性不等于 live route。
- UI 不能直接使用 upstream 63-provider enum 或 Worker 动态 catalog 生成列表；disabled/unreviewed strategy 不得成为可执行入口。

## IMPLEMENTATION_SEQUENCE

### Phase 0 — Decision record

状态：已完成；后续授权将实施边界扩展到后台 build/transport 接线。

- 保存本文。
- 不接入 Xcode/App/Store/UI。

验收：

- 只有报告文件发生变化。

### Phase 1 — Domain and orchestration skeleton

状态：后台部分已完成；Store/cache/UI 迁移按本轮边界明确延后。

- 新增 `CollectionTargetKey`。
- 新增 `ProviderObservation`。
- 新增 static Route Registry。
- 新增 Run Coordinator。
- 新增 fake Native/Collector Engine。
- 将 operation ID、generation 和缓存粒度改为 target key。

验收：

- 全部离线 synthetic。
- 当前 UI 行为不变。
- 不链接或执行 CodexBar Core。

### Phase 2 — Migrate existing native routes

状态：七条 native route 的类型化 backend executor 与 observation bridge 已完成；现有 Store/UI 调用链未切换。

- 将当前 Codex、Claude、Google、OpenRouter native adapter 包装为 observation producer。
- 保持 endpoint、credential、UI 和 Clear 行为不变。
- 验证 Personal/Enterprise、Consumer/Project、Account/Key 不再共享同一状态槽。

验收：

- 现有 84 项及新增 target/account/freshness 测试全部通过。
- UI 与视觉回归无变化。

### Phase 3 — Signed XPC worker and fake end-to-end flow

状态：XPC target、contract、embed、真实 IPC handshake/catalog/default-deny 已完成。当前 Debug 为 ad-hoc 签名；Developer ID release 签名和可验证的 Worker/进程树硬终止尚未完成，因此没有启用 fake 或 live collector route。

- 新增 `DashisCollectorWorker.xpc` target。
- 主 App 只通过 contract/XPC 通信。
- 增加签名、version、schema、output cap、deadline 和 worker termination。
- 先只运行 fake strategy，不触发真实网络/HOME/Keychain/browser/CLI。

验收：

- worker 崩溃、卡死、超时、取消不会污染 Store。
- Clear/new generation 后迟到 outcome 被拒绝。

### Phase 4 — Host services and exact effect manifests

- 建立 HTTP/Credential/Local-State/Keychain/Browser/Subprocess Broker。
- 完成 upstream host-services 注入并升级 pin。
- 为第一个最低副作用、官方只读 strategy 建立 exact manifest。

验收：

- enabled strategy 路径不存在直连 IO 逃逸。
- endpoint、response cap、redirect、credential 和 deadline 测试通过。

### Phase 5 — Codex Personal canary and cutover

- 按本文的迁移规则执行。
- 完成 parity 后切换正式 route。

### Phase 6 — Provider batches

按风险分批：

1. 官方、只读 API。
2. 明确本地文件/CLI，只读且无 credential mutation。
3. OAuth/Keychain，可能 refresh。
4. browser Cookie/private API。
5. potentially billable probe 或远端 mutation。

后两类默认保持关闭，只有单独产品与合规决定后才能启用。

## RELEASE_GATES

一个 CodexBar strategy 只有同时满足以下条件才能进入正式 App route：

1. pinned 源码与 exact effect manifest 完成逐项审查。
2. manifest digest 与 CI 中的代码证据一致。
3. 网络、文件、凭据、Keychain、browser 和 subprocess 都经过 broker。
4. Release 中不存在 custom policy 无条件 allow 的入口。
5. schema、provider、target、strategy、provenance 与 account 验证 fail closed。
6. selected account 在发布前达到 `.resultVerified`。
7. credential writeback 只有最终 outcome 验证后才能事务提交。
8. hard deadline、worker termination、process-tree kill 和 generation guard 通过测试。
9. source、private API、ToS、potential cost 与用户提示完成评审。
10. 自动测试全部使用 synthetic fixture，不读取真实账户。
11. 默认 disabled；不存在“一次打开全部 63 个”的开关。
12. UI 不把经 CodexBar 获取的数据错误标成 native 或 Official。

## REJECTED_ARCHITECTURES

明确拒绝：

- 把 CodexBar 注册成第五个 `ProviderUsageClient`。
- App target 直接 import `CodexBarCore`。
- `CollectorOutcome` 直接压扁成 `ProviderSnapshot`。
- 继续使用 `[ProviderID: ProviderSnapshot]` 承载多产品、多账户。
- blanket `.auto` 或 `CollectorCapability.allCases` 后全量运行。
- native 与 CodexBar 每次同时真实双跑，采用最快返回者。
- 使用 CodexBar CLI 外部安装作为生产依赖。
- 使用 `codexbar serve`、localhost 业务服务或 LAN API。
- 通过 shell、任意 `$PATH` executable 或用户指定脚本运行 provider。
- 为省时间直接修改 vendored Core。
- 因为不进 App Store就关闭签名、公证、deadline、权限或账户验证。
- 把 CodexBar 用户量当成 private endpoint 官方性、安全性或 ToS 授权证明。
- 将不同 product/scope 的百分比合并。
- 用较新的 credits/cost timestamp 给旧 usage 续命。

## PROJECT_AUDIT_SUMMARY

本轮完成后的当前事实：

- Dashis 是 macOS 原生 SwiftUI App。
- 当前 Store 以 provider brand 为 key，尚不能表达正式多账户/多 scope。
- 四个现有 native provider 已有严格 endpoint、凭据、freshness 和 generation 边界。
- `Vendor/CodexBarCore` 已锁定 v0.45.2 / commit `91560ca...`，上游源码零 patch。
- App 已链接 Foundation-only `DashisCollectorContract`；只有嵌入式 XPC Worker 链接 `CodexBarCollector` 与 Core。
- wire v3、rollout catalog handshake、route authorization、target/account/scope model、canonical observation、route registry、run coordinator、native executor、outcome validator 与真实 XPC transport 已完成。
- facade 已有默认拒绝、strategy provenance、selected-account verification 和 schema v2 outcome；Worker production route registry 为空，`liveRouteCount = 0`。
- facade 还不是进程沙箱，Core 仍存在直接网络、HOME、Keychain、browser、subprocess 和 credential mutation。
- Xcode build graph 已嵌入 Worker；Store、Dashboard、Sidebar 与 provider detail 已投影同一份 34-provider catalog。四个 native flow 保持原调用链，另外 30 个入口只有只读 source 元数据，不消费新 runtime 或 `ProviderObservation`。

## DOCS_CONTENT_SUMMARY

- `docs/CURRENT_STATE.md`：记录四 target、App/Worker module boundary、native backend runtime、wire v3 exact authorization、34/52/50 staging catalog、4 native/30 catalog-only 前台边界、100/100 Xcode tests 与 33/33 package tests。
- `docs/PROJECT_MAP.md`：登记 ProviderIntegration、XPC Worker、contract/Core package graph、测试和生成物位置。
- `docs/ARCHITECTURE.md`：固化 native/collector 双引擎、target/account/scope、wall-clock result deadline、XPC default-deny 与 live-route release gate。
- `docs/DO_NOT_BREAK.md`：固化 App 不链接 Core、catalog-only 前台不得触发采集、live route 保持 disabled，以及凭据/effect/process-tree/release signing 禁区。
- `docs/TESTING.md`：加入 wire authorization、native account/interaction、真实 XPC handshake/catalog/default-deny 和离线测试要求。
- `docs/USER_TUTORIAL.md`：说明 34-provider 前台目录、四个 native 操作、30 个只读详情，以及 bundle 内 Worker 仍保持 default-deny。

## VALIDATION_RESULT

- `plutil -lint Dashis.xcodeproj/project.pbxproj Tools/DashisCollectorWorker/Info.plist`：通过。
- `xcodebuild -list -project Dashis.xcodeproj`：发现 `Dashis`、`ClaudeStatusLineHelper`、`DashisTests` 与 `DashisCollectorWorker` 四个 target。
- 最新工作树 `xcodebuild test`：100/100 通过，0 failure；包含 34-provider 前台顺序/唯一性、4 native/30 catalog-only dispatcher 边界、生产 native runtime、Worker route-denial 分类与真实嵌入式 XPC handshake/catalog/default-deny。
- standalone `swift test`：33/33 通过，0 failure；使用已解析的 pinned checkout，完整编译 63-provider Core，并验证 34/52/50 rollout scope、automatic-only 阻断与握手一致性。
- `codesign --verify --deep --strict`：Debug App bundle 通过；App 与 Worker 均为 ad-hoc，Worker bundle ID 为 `com.Vita0818.DashisMac.CollectorWorker`。
- link/import 检查：App source 只 import contract；只有 Worker import `CodexBarCollector`，Core 静态闭包只进入 Worker。
- Dashboard、Sidebar、provider detail、catalog projection 与 `DashisProviderStore` 的前台改动已通过构建和测试；catalog-only dispatcher 为 no-op，不会触发 XPC。
- 已启动构建产物做只读界面验收：Sidebar 与 Dashboard 均显示 34 项，长名称保持单行；catalog-only 行只有低权重 source 摘要和 chevron，详情只显示 `Data sources`，未点击任何采集动作。
- `git diff --check`：通过。

一次使用全新 SwiftPM scratch path 的验证因环境代理 `127.0.0.1:1082` 不可用而无法下载固定依赖；随后使用本机已解析、由 lock 固定的 checkout 完成离线测试。2026-07-30 扩展后的 suite 为 33/33；没有执行真实 provider、网络、HOME、Keychain、浏览器或 CLI 采集。

## UNCERTAINTIES

以下不阻止本轮后台接线完成，但会阻止启用任何 live CodexBar route：

- CodexBar upstream 是否接受完整 host-services 注入接口。
- 第一个最低副作用真实 strategy 的选择。
- 非 App Store 发行使用的 Developer ID、notarization 和更新渠道细节。
- 未来是否批准动态 provider catalog UI。
- 哪些 private/Cookie/billable strategy 最终被产品策略永久禁用。
- operation-scoped Worker/PID/签名验证与不可协作 Core/CLI 的进程树 TERM/KILL escalation。
- 所有 canonical native observation 的统一时间/字符串上限 validator，应在未来 Store projection 前补齐；当前 production native adapter 的既有 decoder/endpoint 边界和 collector validator 已覆盖本轮执行链。

如果 upstream 不提供 host-services 注入，对应 live strategy 保持 disabled；不得通过修改 Vendor 或放宽全局安全边界绕过。

## NEXT_RECOMMENDED_ACTION

下一步先让用户验收 34-provider 目录的信息层级；若继续推进 live 接线，只选择一条最低副作用、官方只读 strategy，完成逐 effect manifest、host broker、operation-scoped hard termination 与 Developer ID release 签名。上述 gate 全部验收前，Worker route registry 继续为空；不一次性启用 34 个 selected provider 或全部 63 个 upstream provider。
