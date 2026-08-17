# CURRENT_STATE

## 当前状态

- 项目名：Dashis；独立 Git root 为 `/Users/vita/Vitemis/Dashis`，远程 `origin` 为 `https://github.com/Vita0818/Dashis.git`。
- 当前产品是 macOS 原生 SwiftUI provider-first dashboard；没有 WebView、网页入口、Node gateway 或旧 mock telemetry/runs。
- `Dashis.xcodeproj` 当前包含四个 target：macOS App `Dashis`、命令行 helper `ClaudeStatusLineHelper`、XPC service `DashisCollectorWorker`、单元测试 `DashisTests`。shared scheme `Dashis` 会构建 App、helper 与嵌入式 Worker，并运行测试 target。
- `script/build_and_run.sh` 是本地 build/run 入口；`.codex/environments/environment.toml` 的 Run action 调用该脚本。
- CodexBar 后台接线已进入 Xcode build graph：`Vendor/CodexBarCore` 固定 CodexBar v0.45.2 的完整采集 Core，`Packages/DashisCodexBarCollector` 提供稳定 contract、显式 live route catalog、逐操作 exact policy 与 facade。主 App 只链接 Foundation-only `DashisCollectorContract`；`CodexBarCollector` 与 Core 只链接到嵌入式 `DashisCollectorWorker.xpc`。30 个扩展 provider 已通过 41 条 live explicit route 接到 Worker；Codex、Claude、Gemini 和 OpenRouter 四个 provider 仍走现有 native 实现。
- 当前只实现 macOS；iOS target 仍为 `UNKNOWN`。

## 已实现能力

### 统一 provider 模型

- Sidebar 继续由唯一外层 macOS 原生 `NavigationSplitView` 中的 `List(selection:)`、系统 section 与选中态接管导航，主 Sidebar 不放搜索框；Dashis 已有品牌资产是明确例外：列表顶部保留原来的 28 pt semibold Serif `Dashis`、原始 vertical padding 与 `x: 7 / y: 9` 位置。主 Sidebar 固定为 218 pt，并使用新的稳定 List identity 丢弃此前嵌套 split 留下的恢复状态；Dashboard、Settings 与 provider 行都允许在该列内压缩并尾部截断。其后显示 `Dashboard`、唯一顶层 `Settings` 入口和当前开启的 provider；provider 行不恢复泛化图标、手绘浅蓝选中态或逐行 offset。Codex、Claude、Gemini（内部导航 ID 仍为 `google`）和 OpenRouter 复用现有 native 数据流，其余 30 个继续使用 `.collector` 集成。没有动态 Add provider，也没有重复的 `Providers` 页面。
- 所有 adapter 最终投影为 `ProviderSnapshot` / `QuotaWindow`。Dashboard 使用原生 `ScrollView` + 自适应 `LazyVGrid`，按固定 catalog 顺序显示当前开启 provider 的统一系统 `GroupBox` 展示卡：宽窗口双列、窄窗口单列。每张卡只负责打开相应的纯数据展示页，不直接检查、连接或显示 `Configure` 按钮。卡内复用同一类型化 projection，订阅/限额型数据优先实际返回的两个主窗口，余额型在没有窗口时优先真实 balance；collector 未检查时显示诚实的 `Not checked`。不会伪造余额、窗口、连接状态或指标数。所有 provider 都关闭时，Dashboard 显示系统空态并指向 Settings。
- 展示与配置已经分离。直接选择 provider 会打开最大 900 pt 的纯数据 `ScrollView`，其中只有一张统一的系统 `GroupBox` 主卡；尚未采集时只呈现 provider 名称与诚实空态，有 snapshot 时才加入真实数据，不出现 method、credential、consent、Check 或 Clear 控件。选择顶层 `Settings` 后进入第二层 provider 菜单；完整 34-provider catalog 始终保留在这里并可独立搜索，每一行右侧使用系统原生 switch 控制该 provider 是否显示在主 Sidebar 与 Dashboard。关闭只改变展示集合，不删除 snapshot、配置、路由或采集能力；隐藏 ID 作为非敏感偏好写入 UserDefaults，重启后仍生效，重新打开即可恢复。右侧才显示最大 900 pt 的 grouped `Form`。30 个 collector 只保留 Connection、按需出现的 Credentials、唯一主操作和 Advanced；没有配置字段时不再显示重复的 Access section。method 说明、内存生命周期 footer、常驻风险卡和 Advanced 运行说明均已删除。高风险 route 只在点击 `Check Usage` 后显示一次确认对话框，consent 与 Worker 复核保持不变。Codex、Claude、Gemini、OpenRouter 的常驻解释 footer 同样删除，只保留字段、状态结果和实际操作。route/source/strategy 仍收进单一 `Advanced` disclosure，`Clear` 仅在有可清状态时出现在 section header 的更多操作菜单。成功结果按 `CollectorOutcome → ProviderObservation → ProviderSnapshot` 投影回展示页；`opencodego.local`、`kimi.cli`、`mimo.local` 三条 automatic-only strategy 不会出现在 method 列表中。
- 数据来源分为 `officialDirect`、`officialDerived`、`officialLocalBridge`、`experimentalPrivate`、`manualOnly`；UI 不把推导值、私有 endpoint 或手动值伪装成官方实时余额。
- 原始 remaining 允许为负数；只有服务端返回 percentage，或存在可验证 numerator/denominator 时才显示进度，且仅视觉 fraction 投影到 `0...1`。未知 denominator、limit-only 或 KPI metric 不伪造 `0%` 进度。provider 主卡内部最多突出两个主指标：订阅型数据优先展示 5-hour/7-day 等用量窗口；没有窗口但有余额时只突出余额，其余 metric 收进同一卡片的折叠区；窗口与余额都没有时才突出前两个 metric。两个主指标不再各自套小卡，而是在一张主卡内以同层级 pane 排列，窄宽度自动纵向排列。窗口存在时的余额、其余 balance/metric 和 source/scope/observed metadata 同样收进主卡 disclosure；完整 warning/failure 在卡内各展示一次且不另套 surface。

### Codex

- Personal：只有用户点击检查时才以普通文件、非 symlink、当前 UID、大小与权限约束读取 `~/.codex/auth.json`；调用两个非公开 `wham` endpoint，来源标为 `Experimental`。
- Personal usage 会读取账户实际返回的 plan、`credits.balance` / `credits.unlimited` / `credits.has_credits` 与可选 usage windows；没有窗口时不虚构固定滚动周期，也不再把 `primary_window` 硬编码成 5 小时。
- Personal usage 与 available reset credits 独立请求；其中一个失败时保留另一个结果并展示 partial failure。账户 credits 与 reset credits 是不同字段，UI 不混为同一余额。
- Enterprise：使用用户临时提供的 analytics API key 与 workspace ID 调用官方 Codex Analytics usage endpoint，最多 100 页、每页 500 条，来源标为 `Official`。
- API key/token 不写入磁盘、UserDefaults、Keychain、日志、fixture 或文档。

### Claude

- 用户显式点击 `Preview connect` 后，Dashis 只验证 bundled helper、读取 `~/.claude/settings.json` 并展示字段级变更摘要，不做持久写入；第二次 `Apply change` 才安装/更新私有 App Support helper 并写入经过复核的 Claude settings patch。
- 独立 helper `dashis-claude-statusline` 接收 Claude Code 官方 statusLine JSON，只保存净化后的 schema version、observed time、5-hour/7-day used percentage 与 reset time。
- helper 保留并执行用户原有 statusLine command，向其传递完全相同的 stdin，并转发 stdout、stderr 与退出状态。
- snapshot 最大 8 KiB，要求普通文件、当前 UID、私有权限；缺少 `rate_limits` 不覆盖旧值，单窗口可独立更新，毫秒 epoch 和越界百分比被拒绝。
- Disconnect 恢复原 statusLine；Clear/Disconnect 可删除经过验证的净化 snapshot。Dashis 不会为了刷新配额自动发送 Claude 请求。

### Gemini（现有 Google AI native flow）

- Consumer subscription：没有受支持的第三方余额 API，摘要只显示 `No quota data`；录入真实手动值后才显示 `Manual` 限定词。用户可显式打开 Gemini 官方页面，或录入带采集时间的手动值。
- Consumer 模式不读取浏览器 Cookie、profile、Gemini/Antigravity 私有 OAuth 文件、Keychain 或 TUI 输出。
- Gemini API project：用系统默认浏览器发起 Google Desktop OAuth，使用随机 `127.0.0.1` loopback callback、PKCE S256 与 state；project ID/number 由用户手工输入，只保留 session access token，丢弃 refresh token 与 ID token。
- Project 模式分页读取 Cloud Quotas `QuotaInfo`，再用 exact metric type 查询 Cloud Monitoring；按 quota dimensions/model/location 匹配，usage 可跨 method 聚合。可选 quota ID 输入支持逗号或空白分隔；留空时自动选择被限制为最多 24 个 quota definition，Monitoring 的 FULL point 分页会先按完整 labels 合并。
- DELTA 求和、GAUGE 取最新值；分钟/小时 quota 选择最新完整且已可见的公共历史窗口，摘要明确标为 historical，detail 只在对应 window/warning 中给出一次 exact as-of，绝不冒充当前实时窗口；未知 refresh interval 不计算 remaining。RPD 使用 `America/Los_Angeles` 日历午夜，结果标为 `Official · Estimated` 并显示约 150 秒 Monitoring 延迟。
- 授权主体需要可执行 `cloudquotas.quotas.get` 与 `monitoring.timeSeries.list`；Consumer 的 Antigravity quota/credits 只提供 CLI `/credits` 人工查看指引。

### OpenRouter

- 默认 `Account` 模式使用用户显式提供、仅保存在当前 session 的 management key，直接查询账户级 credits、无单-key过滤的 activity、analytics meta/query 和可选 generation；单项失败不会抹掉其它数据。账户 remaining 按官方 `total_credits - total_usage` 计算。
- `/activity` 是最近 30 个已完成 UTC 日的账户级聚合，不是逐调用原始日志；自选 1–90 天趋势走显式 time range 的 beta analytics。账户检查成功后，独立的 `Recent calls · metadata only` disclosure 可按 1–30 天窗口读取最多 20 条带 `generation_id` 的账户级 analytics 行；该 sidecar 不写入 `ProviderSnapshot`，失败也不会清掉已成功的余额。
- Recent calls 只显示 generation ID、时间 bucket、可用的 key/model 标签、usage/cost 和 token 等 analytics metadata。更改窗口会先清掉旧列表，避免新控件值与旧查询口径并存。OpenRouter 没有公开的完整、可分页逐调用列表；结果可能被截断或去重，Dashis 不把它称为全部/最新日志，也不读取 prompt/completion 内容或 `/generation/content`。
- 可选 `Single key` 模式保留官方 OAuth PKCE，在默认浏览器与随机 `127.0.0.1` callback 上取得用户控制的 API key，再以 `/api/v1/key` 读取该 key 自己的 limit/usage/remaining；官方 OpenRouter flow 没有 state，当前实现以高熵随机 callback path、精确 path 校验和 PKCE 隔离会话；key 仅存当前 app session。
- Management key 本身可管理账户 key，但 Dashis 的 endpoint allowlist 不开放 `/api/v1/keys` 创建、更新或删除接口；当前只允许账户读取/分析请求。Management key 不能用于模型 completion。
- Analytics 请求先读 `/analytics/meta` 再选择实际存在且可加总的 metric/dimension；rate metric 被排除。`metadata.truncated` 时自动把时间窗缩小一半重试一次，并明确显示实际采用的较窄窗口或仍不完整警告。
- remaining 不钳制负值；token total 优先官方 `total_tokens`，fallback 为 prompt + completion，reasoning 只作 output breakdown，不重复相加。
- 不把不同日期、模型或 endpoint 的 rate metric 相加成伪造总 rate。`Clear` 会清除 Dashis 本地 OAuth/key 状态，但若服务端可能已经创建 key，用户仍需在 OpenRouter 官方账户页 revoke。

### CodexBar 后台采集接线

- `Vendor/CodexBarCore` 锁定最新稳定发布 `v0.45.2` 的实际源码 commit `91560ca98e776b96fdf910d4a0423c2f0c07a3b9`；`Sources/CodexBarCore` 的 474 个 Swift 文件、63 个 provider descriptor、`CSQLite3` shim、MIT 许可证和可选 Claude watchdog 均已原样保留，上游源码零本地 patch。
- 精简 SwiftPM manifest 只包含采集 Core 的运行闭包：SweetCookieKit 0.4.1、swift-crypto 3.15.1、swift-log 1.13.2 与传递依赖 swift-asn1 1.7.1；版本和 revision 由 `Package.resolved` 固定，许可证与 NOTICE 位于 `Vendor/CodexBarCore/LICENSES/`。
- `Packages/DashisCodexBarCollector` 分为 Foundation-only `DashisCollectorContract` 与 live `CodexBarCollector`。schema v2 结果 envelope 保留 provider/account resolution、请求与实际 source、strategy、attempt、raw used/remaining percentage、window/reset、confidence、可空 credits balance、component timestamp、sanitized diagnostic、OpenAI dashboard、Claude credential comparison 与六类 live-only provider artifact；remaining 使用 `100 - usedPercent`，不会二次钳制。
- `DashisCollectorContract` 现在提供 wire v4 的 Data-only XPC protocol：日期固定为 Unix 毫秒，request/response 上限分别为 256 KiB/2 MiB，budget 限制为 1–120000 ms，并拒绝含糊的 `.auto` source。collect 必须携带 exact route ID、strategy ID/kind、route-manifest SHA-256、upstream pin、live catalog revision、一次性 broker lease 和本次 consent 状态；握手固定 rollout catalog revision、34/52/50 staging 数量、41 条 live route、live revision 与 manifest-set digest，App 与 Worker 不跨进程传递 Core 对象。
- `CollectorRolloutCatalog` 锁定用户选择的 34 个 provider、52 条 pinned exact strategy 和 50 条非 `.auto` source binding；每条 strategy 记录源码审计中已观察到的网络、凭据、本地状态、浏览器、Keychain、子进程、写回、远程 mutation、endpoint override 或潜在费用风险。该清单只是 staging/review 事实，不是完整 effect manifest，也不是执行许可。`opencodego.local`、`kimi.cli`、`mimo.local` 只能由上游 `.auto` planner 进入，当前明确没有 exact binding。
- `CollectorLiveRouteCatalog` 用独立、显式冻结的 binding ID 列表从 50 条 staging binding 中排除四个 native provider 的重叠路径，并为其余 30 个 provider 固定 41 条 live explicit route；新增 staging binding 不会自动上线。每条 route 固定 provider/source/exact strategy、route-manifest digest、upstream pin、允许的临时配置字段、交互类型、风险摘要和是否需要逐次 consent。该 digest 绑定 route 执行字段，不应误称为完整 effect manifest；未知 route、`.auto` source、三条 automatic-only strategy 与 manifest/pin/revision 不匹配均继续 default-deny。
- `App/macOS/ProviderIntegration` 已建立 `CollectionTargetKey`、canonical `ProviderObservation`、不可变 fail-closed route registry、native snapshot bridge、Collector outcome validator/mapper 与按 target generation 隔离迟到结果的 `ProviderRunCoordinator`。生产 registry 保留四个 native provider 的七条 native route，并追加 41 条 collector route；collector 详情通过 Store 调用 `ProviderCollectionRuntime`，形成 `App → XPC Worker → exact single-strategy policy → CollectorOutcome → ProviderObservation → ProviderSnapshot` 的真实链路。
- `DashisCollectorWorker.xpc` 已嵌入 `Dashis.app/Contents/XPCServices/`，只在 Worker 内链接 `CodexBarCollector`/Core。Worker 采用单任务并发、重复 request-ID 拒绝、有限 payload 与净化错误；握手报告 rollout revision、34/52/50 staging 数量、41 条 live route、live revision 与 manifest-set digest。每次 collect 会复核全部 exact authorization 字段，再为该操作构造只含一个 request rule、一个 planning rule 和一个 exact strategy rule 的 collector policy。
- App 通过 connection-scoped、one-run reverse configuration broker 向 Worker 只释放 exact route 声明的配置键；broker 与 request ID、route ID、lease ID 绑定，最多解析一次，完成后移除值。Settings 表单临时值只保存在 App 内存，不写入磁盘、UserDefaults 或 Keychain；当前 route 声明且已存在于 App 启动环境中的键也会经同一 lease 释放，页面输入优先。字段留空时，strategy 仍可能使用受支持的本地 provider/CLI/browser 配置。
- Worker 启动后先删除除明确 runtime/test-safety allowlist 外的全部继承环境变量；每次操作再把 broker 允许键临时安装到 facade context 和真实 Worker process environment，兼容 Core 的直接 `ProcessInfo` 读取与子进程继承，操作结束立即恢复。facade 同时拒绝未经 exact route 授权的 request/planning/strategy，并禁用持久 CLI session 与 `debugKeepCLISessionsAlive`。这仍不是完整 sandbox：broker 不代理 Core 的 HTTP、HOME 下 provider 文件、Keychain、浏览器或子进程访问；Core 的 login-shell locator 还可能按用户 shell 配置自行加载环境。
- 非 ambient account 必须包含稳定 UUID，并由 host account resolver 返回匹配的确认 ID、完整替换 ambient 值的 account-specific context，以及带稳定 email/provider account-ID anchor 的 identity expectation；否则在 strategy resolution 前拒绝。fetch 后还会校验 provider-reported identity 与 dashboard email，只有一致时才发布 payload 并标为 `.resultVerified`，缺失或冲突时整包拒绝且不 fallback。
- 上游 fetch 返回的 strategy ID/kind 必须与通过 exact policy 的 strategy 完全一致；不一致时按 provenance failure 拒绝，不把结果伪装成已授权来源。
- 该 policy 与 XPC 进程边界都不是完整 OS sandbox。已授权 strategy 仍可能使用 Core 自己的网络客户端，读取 provider 文件、Keychain 或浏览器数据，启动 CLI，或刷新凭据。deadline 会先 cooperative cancel，再调用 `collector.shutdown()` 关闭 Core 持久会话，等待 2 秒 grace；仍未退出时终止 Worker 自有 process group 并 `_exit(124)`。这为当前 operation 提供了硬停止兜底，但尚未证明能捕获所有自行脱离 process group 的后代进程，文档、UI 和测试不得把它描述成完整进程树 sandbox。
- 当前 facade 可注入显式 environment、provider environment、完整 `ProviderSettingsSnapshot`、account resolver 与 host-owned token update callbacks。Dashis 已完成 outcome→`ProviderObservation`→`ProviderSnapshot` 映射、41 条 live route、one-run configuration broker 和 30 个 collector provider 的 method/config/check/consent/clear UI；四个 native provider 不迁移到 CodexBar。

### 安全网络与验证

- `ProviderHTTPClient` 使用 ephemeral `URLSessionConfiguration`，禁用 cache、cookie 与 credential store；所有 redirect 均拒绝，429/502/503/504 与有限瞬时网络错误最多重试一次。
- `ProviderEndpointPolicy` 同时校验 HTTPS、精确 host/path、method、query、body schema 与端口；OAuth 授权 URL 和 localhost callback 另有严格校验。
- `Clear` 会失效当前 provider generation、关闭活动 OAuth listener，并清除临时 key/token、输入、PKCE/OAuth 会话引用与内存 snapshot，避免迟到响应重新写回。
- `DashisTests` 使用纯合成、离线数据；除既有 decoder、projection、provider correctness 与安全边界外，还覆盖 34-provider catalog 顺序与唯一性、4 native/30 collector 行为边界、provider 展示开关的隐藏/恢复/跨 Store 持久化与 Settings 完整目录不变、41 条 live explicit route、target identity、native/collector route registry、wire v4、reverse broker codec、`.auto`/未知 route 拒绝、逐次 consent、合成 live outcome provenance、Observation→Snapshot projection 与嵌入式 XPC 握手；不访问真实账户或执行真实 provider。

### UI 与视觉验收

- 主界面以 macOS 26/27 的系统结构为 source of truth，但整扇窗口只允许一个系统默认样式的 `NavigationSplitView`。2026-08-17 的两张实际 1160 × 760 窗口截图证明，在外层 detail 内再嵌套第二个 `NavigationSplitView` 会产生不可接受的系统恢复状态：第一张把主 List 的 leading edge 推出窗口，第二张即使锁定 218/220 后仍把二级 Sidebar 自动折叠、生成右上角双箭头，并保留主 List 横向错位。因此 `DashisWindowLayout` 只把唯一主 Sidebar 锁为 218 pt；Settings 二级菜单是外层 detail 内固定 220 pt、不可折叠的 `HStack` 子面板，使用原生 `NSSearchField`、系统 `.inset` `List`、`.switch` `Toggle` 与被动 `Divider`，右侧 grouped `Form` 吸收剩余宽度。二级菜单没有 column visibility、split divider 或 toolbar toggle。完整 provider 名称可压缩、单行尾部截断，switch 固定为系统尺寸，不能靠额外横向 spacing、非零最小 `Spacer` 或左右 padding 撑开面板。`navigationTitle`、Dashboard `ScrollView` / `LazyVGrid` / `GroupBox`、纯展示 `ScrollView`、grouped `Form`、`Section`、`LabeledContent`、`ProgressView`、`Picker`、`DisclosureGroup`、`Menu` 和按钮继续采用系统样式。Sidebar 顶部原有的 28 pt Serif `Dashis` 品牌及其位置属于受保护的 Dashis 身份；品牌之外的控件和 light/dark surface 仍交给系统。若上次顶层页面停在 Settings，下次启动会先回到 Dashboard；用户仍可正常点击 Settings 进入配置工作区。
- Settings 始终保留完整 34-provider catalog；Sidebar 与 Dashboard 使用由每个 provider 原生开关投影出的可见子集，默认全部开启。主 Sidebar 没有搜索。普通导航与 Dashboard 卡片不显示 provider 泛化图标、chevron、连接 badge 或指标数量；仅真实 warning/failure 限定与更多操作保留必要语义。
- Settings 中每个 provider 配置屏只保留一个当前可执行的主操作。次要连接选项放进对应 disclosure，`Clear` 放进 section 尾部的更多操作菜单，route/source/strategy 收进单一 `Advanced`；正常状态不显示方法解释、凭据生命周期、常驻风险、重复 caption 或装饰性按钮。真实错误、warning、stale/expired 和操作时确认仍按状态出现。展示页不出现这些配置控件。
- Dashboard 的每个 provider 也是一张低噪声系统 `GroupBox` 展示卡：卡头只保留名称和必要异常/来源限定，卡内最多两个同层主数据 pane；订阅优先 5-hour/7-day 等真实窗口，没有窗口时余额优先，无数据时只保留诚实主空态。Dashboard 卡不显示 metadata、配置或按钮，整卡进入完整展示页。每个 provider 展示页继续只有一张更完整的系统 `GroupBox` 主卡；额外用量与 metadata 只在该详情卡的 disclosure 中出现。两处都不嵌套小卡，也不使用手绘背景、进度轨道或装饰性阴影。
- Codex 网页只作为 quota/balance 信息层级和去重方式的参考；最终壳层遵循 macOS 原生 `NavigationSplitView`、`List`、搜索、toolbar、按钮与 disclosure 习惯。
- `--visual-qa` 只在 Debug 构建中注入合成 Codex snapshot 并打开 Codex detail；当前样本包含 5-hour、7-day 两个主窗口与一个次级余额，用于验证主次层级和折叠行为。fixture 初始化不读取账户文件、provider credential 或真实响应，也不会自动发起网络检查；Release 构建不启用该 fixture。

## 当前验证状态

- 2026-08-17 第二张实际窗口截图证伪了双层 split 的最终可行性：主列背景虽为 218 pt，但 List 内容仍错位，内层 Settings Sidebar 被系统完全折叠并在右上角出现恢复按钮。最终修复删除内层 `NavigationSplitView`，只保留唯一外层 split；Settings 改为固定 220 pt 的 `NSSearchField + .inset List + switch` 面板和可伸缩 Form，主/二级 List 使用新的 view identity。一个不显示到桌面的原生 `NSHostingView` 结构探针按 1160 × 760 离屏渲染最终单 split 结构，确认完整 `Dashis`/Dashboard/Settings/provider leading edge、固定二级菜单、搜索、长名称、switch 与右侧 Form 同时存在，且源码中不再有第二个 column visibility 或双箭头来源。最终静默 `xcodebuild build-for-testing` 通过，使用 Xcode 27 / macOS SDK 27；App、Worker、helper 与 `DashisTests` 均可编译链接。为避免再弹出窗口，本轮没有执行会启动 macOS test host 的 shared-scheme `xcodebuild test`；同一 41-route 后台最近一次完整基线仍是 105/105、0 failure。
- 2026-08-17 设置页常驻提示清理后的增量静默 `build-for-testing` 通过。源码扫描确认没有 Form footer、method/access/lifecycle 提示、常驻 consent section、Advanced 运行说明或 Recent Calls 前置引导；逐次 consent alert、真实状态、错误、warning 与 truncation 结果仍保留。
- 启动产品后不会自动调用任何 collector provider；Sidebar、Dashboard 和 provider 展示页都只做导航/展示。只有用户进入 `Settings`、选择 provider 并点击对应的 `Check Usage` 或 native 检查动作，才会创建一次采集操作。
- 本轮使用用户提供的两张真实截图确认了两个连续修复前问题；第二次只读应用状态显示 Dashis 已关闭，因此没有调用会重新启动 App 的界面读取。最终源码通过 SDK 编译与单 split 离屏原生结构渲染，但完整 Dashis App 的修复后窗口仍需下一次自然启动时复核；离屏探针不能替代完整产品的 toolbar、材质、滚动和交互验收。原有 Dashis 品牌的 28 pt Serif、位置和主文字色没有改动，主 Sidebar 稳定为 218 pt；旧的 provider 泛化图标、手绘选中态和非原生配置堆叠不恢复。
- 当前 standalone collector package tests 通过：35/35，0 failure；覆盖 wire v4、41 条 live route、manifest-set digest、broker codec、exact authorization 与 consent。测试设计仍禁止真实 provider、浏览器、Keychain、HOME credential 或 CLI。
- `CodexBarClaudeWatchdog` standalone product：通过 SwiftPM build；当前只证明可构建，未嵌入 Dashis App。
- 真实 provider 账户仍需用户在 UI 中主动授权后人工验收；自动测试不会读取任何真实凭据。

## 未确认

- iOS target、共享代码边界与移动端 OAuth/bridge 方案。
- dashboard 的长期用户角色、业务 KPI、刷新调度、通知、数据保留和后端需求。
- 是否允许未来将 OpenRouter/Google refresh token 持久化到 Keychain；当前明确不持久化。
- Codex personal `wham` 是非公开契约，可能随时变化；账户是否返回固定窗口、credits 或 unlimited 状态取决于当前计划与服务端响应，失败时必须继续 fail closed。
- Google consumer subscription 若未来发布正式余额 API，需要重新评估，不能沿用网页或 TUI 抓取。
- CodexBar 后台 transport、领域模型、build wiring、41 条 live explicit route、30 个 collector provider UI、one-run configuration broker、Worker inherited-environment scrub 与 deadline hard-stop 兜底已接通。仍未完成的是完整 host HTTP/Credential/LocalState/Keychain/Browser/Subprocess broker、所有自行脱离 Worker process group 的后代进程终止证明，以及 `ProviderSettingsSnapshot` 的逐 provider 前台映射；这些限制不能被描述成完全 sandbox。
- 非 App Store 分发路线已经确定，但当前 Debug 产物仍为 ad-hoc 签名。正式发布前仍需为 App/Worker/辅助 executable 配置同一 Developer ID、Hardened Runtime 与 notarization，并验证固定 bundle 路径、签名、Team ID 和版本。

## 工作区注意

- 工作树改动以每轮开始时的 `git status --short -- .` 为准；不得清理、回退或覆盖用户已有改动。
- 未经明确请求，不 add、commit、push 或创建 PR。
- 真实账号数据仅能通过用户显式操作进入当前 app session；不得把凭据、完整响应或私人路径写入仓库。
