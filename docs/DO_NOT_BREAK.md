# DO_NOT_BREAK

本文列出 Dashis 当前不可破坏的工程、数据、provider 和用户流程边界。源码、工程配置与测试是当前事实；不能把未确认能力写成已实现。

## 仓库与工程禁区

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、验证或准备工作不等于提交请求。
- 若用户要求提交，只处理当前 Git root 中与任务相关的文件；不递归修改、暂存、提交或推送 submodule、nested Git repo 或依赖 checkout。
- 不安装依赖、初始化新构建工具或修改 Vitemis 其它项目，除非用户明确要求。
- 不删除或降级 `Dashis`、`ClaudeStatusLineHelper`、`DashisCollectorWorker`、`DashisTests` target、shared `Dashis` scheme、App 对 helper/Worker 的依赖、`Embed Claude Helper` 或 XPC embed phase。
- 不把 build 生成物写进仓库；DerivedData 继续使用系统临时目录或显式的临时路径。
- `Vendor/CodexBarCore/Sources/CodexBarCore`、`Sources/CSQLite3` 与 `Sources/CodexBarClaudeWatchdog` 必须保持与固定 upstream commit 字节一致；不得直接打补丁。升级只能整体换 pin，并同步 `UPSTREAM.md`、`PATCHES.md`、依赖 lock、许可证和测试。
- CodexBar 后台 build/transport 接线已经获批，但 module boundary 不得放宽：App target 只能链接 Foundation-only `DashisCollectorContract`；`CodexBarCollector` 与 `CodexBarCore` 只能链接 `DashisCollectorWorker`。不得让 Store/UI、既有 provider client 或其它 App source import Core/live collector。
- SwiftPM build/test 的 scratch path 必须在系统临时目录；不得把 `.build`、dependency checkout、真实 config 或 probe dump 写入仓库。
- iOS target 与共享代码边界尚未确认；不得提前把 `App/macOS` 移成跨平台共享层或声称已有 iOS 支持。

## 产品与 UI 禁区

- 不把 Dashis 退回网页形式：不重新引入 `WKWebView`、Web dashboard 主入口、Node localhost gateway、React/Vite/Next 或静态 HTML/CSS/JS dashboard。
- Dashboard 必须保持 provider-first：完整 reviewed 34-provider catalog 始终存在于 Settings 二级菜单；主 Sidebar 与 Dashboard 按 catalog 顺序显示用户通过 Settings 原生 switch 开启的子集，默认全部开启。除此之外不得通过 `isBuiltIn`、snapshot、freshness、loading 或采集状态自动隐藏任何 provider。关闭只改变两个展示入口，不能删除 provider、snapshot、配置、route、observation 或采集能力；Settings 中必须始终能重新开启。Codex、Claude、Gemini、OpenRouter 仍是四个 native 集成，其余 30 个仍走统一 `.collector` 集成。必须保留唯一顶层 `Settings` 入口，不得恢复重复的 `Providers` 页面或说明型/占位 Settings。
- Sidebar 列表顶部必须保留 Dashis 原有品牌实现，不得再以“系统原生化”为由替换或删除：`Dashis` 使用 28 pt semibold Serif、原 vertical padding、`x: 7 / y: 9` 位置与品牌主文字色，Sidebar 的 min/ideal/max 必须同时保持 218 pt；品牌不可选择且不依赖可能被 toolbar 省略的 `navigationTitle`。
- 不恢复动态 Add provider、自定义 session provider、旧 Models/Runs/Alerts、首页小指标网格、右侧 inspector-first、Recent monitors、timeline、额外品牌图标/subtitle/背景或 marketing landing page。受保护的 Serif 文本品牌本身不属于应删除的装饰噪声。
- 不把主题改成 Intatis 的香槟金、暖米色、紫蓝渐变、深蓝 slate 或其它品牌色页面；页面、Sidebar、列表、表单、toolbar、搜索、选中态和普通文本颜色必须继续交给系统 semantic appearance，语义色只表达状态。
- macOS 26/27 原生壳层是当前受保护的视觉契约：全窗口只能有一个默认样式的系统 `NavigationSplitView` 和 218 pt `.sidebar` `List(selection:)`。Settings detail 内使用固定 220 pt 的原生 `NSSearchField + .inset List + .switch Toggle` 面板、被动系统 `Divider`、`navigationTitle` 与 grouped `Form`；Dashboard 继续使用 `ScrollView` / `LazyVGrid` / `GroupBox`，其余控件继续使用系统 `Section`、`LabeledContent`、`ProgressView`、`Picker`、`DisclosureGroup`、`Menu` 与按钮。主 Sidebar 不放搜索。唯一品牌例外是上一条明确锁定的 Serif/位置/宽度；不得把 serif、手工 offset 或其它固定几何扩散到 provider 导航与普通正文，不得恢复定制浅蓝描边选中态、强制页面背景、自绘玻璃、自绘进度条或卡片阴影。代码/route ID 才可局部使用 monospace。
- Settings 二级菜单不得使用第二个 `NavigationSplitView`、`NavigationStack`、`HSplitView` 或其它带独立 column visibility / toolbar toggle / 可拖动 divider 的导航容器；两张实际 1160 × 760 截图已经证明嵌套 split 会裁切主 List、折叠二级菜单并生成右上角恢复按钮。必须保持外层 detail 内零间距 `HStack`、固定 220 pt 面板、原生 `NSSearchField`、系统 `.inset` List、被动 `Divider` 和可伸缩 Form。主 Sidebar 必须维持 `218 / 218 / 218`；主/二级 List 的稳定 identity 不得删除或复用旧嵌套结构的 identity。provider 行不得用显式水平 spacing、非零最小 `Spacer`、额外左右 padding 或长名称固有宽度去撑开面板；名称必须单行、可压缩、尾部截断并保留 tooltip，switch 必须固定为系统尺寸。任何会改变这些结构、宽度或启动恢复页面的调整，都必须先做默认 1160 × 760 与最小 960 × 640 的前台窗口验收，不能仅凭编译通过接受。
- 普通 provider 导航和 Dashboard 卡不得使用无法准确区分 provider 的 `network`、`cloud`、`terminal`、`globe` 等泛化图标、装饰性 chevron、连接 badge 或指标数量。只有 warning、failure 和更多操作等有明确状态/行为语义的位置可以保留系统 symbol。
- Sidebar provider 行与 Dashboard provider 卡只能进入纯数据展示页，不得执行采集，也不得显示 Check、Connect、Configure、credential、method、consent、Clear 或 Advanced 控件。所有这些配置与动作必须只从顶层 `Settings` 进入，再经二级 provider 菜单找到；选择 Settings 中的 provider 本身也不得自动采集。
- 一个页面同一状态只保留一个主要操作。检查/连接/重载等当前任务可用 bordered-prominent；`Clear` 只在确有本地状态时出现在更多操作菜单，不能与主操作争夺视觉优先级，也不能因此弱化原有确认、generation invalidation 或服务端 revoke 提示。
- Dashboard 必须按 catalog 顺序保留当前开启 provider 的统一系统展示卡，并在内容宽度允许时双列、空间不足时单列；全部关闭时必须使用系统空态指向 Settings。不得退回只有 provider 名称和右侧摘要值的普通列表行，也不得恢复旧首页小指标卡墙。Dashboard 卡与 provider 展示页无 snapshot 时只能显示 provider 名称与诚实空态，不得伪造明细；四个 native provider 不得改走 CodexBar。展示页必须保持纯数据 `ScrollView`，不得嵌入 grouped Form 或任何设置 section。Settings 二级菜单必须持续显示完整 34 项及每项系统 switch；配置页必须在最大 900 pt 的 grouped `Form` 内使用真实系统 section 和对齐控件，不得把凭据、风险、按钮或全部配置塞进主卡。collector 常规层级保持 `Connection → Credentials（按需）→ Check Usage → Advanced`；不得恢复 method 说明、Access 重复行、凭据生命周期 footer、常驻风险卡、Advanced 运行说明或 Recent Calls 前置引导。高风险摘要必须只在点击主操作后的逐次确认对话框出现，不能删除 consent gate。native provider 按各自任务分组，但不得恢复常驻解释 footer。exact route/source/strategy 放入单一 `Advanced` disclosure，不得暴露 automatic-only strategy、任意环境变量输入或伪造 snapshot。有 snapshot 时必须经 `ProviderObservation → ProviderSnapshot` 类型化 projection 展示完整归一化窗口、warning 或 partial failure，而且同一份数据只展示一次。
- Dashboard 每个 provider 和 provider 展示页都只使用一张系统 `GroupBox` 外层卡；不得在任一外层卡里再拆成两张或更多指标小卡。Dashboard 卡必须复用详情的类型化优先级，但只保留最多两个主 pane，不承载 metadata 或设置。订阅/限额型结果优先显示实际返回的主窗口；当 provider 实际提供 5-hour 与 7-day 时，这两个窗口必须优先，但不得凭字段名或计划硬编码伪造。余额/充值型结果在没有主窗口时必须把真实 balance 放在第一视觉层级。额外 quota/metric 与 metadata 只在详情主卡内默认折叠；warning/failure 在详情卡内各完整展示一次但不套额外 surface，Dashboard 仅保留必要异常限定。
- 不为 source/scope/observed、warning、failure 或每条普通 metadata 单独套卡片/边框，也不在 provider 展示页同时复制完整 Dashboard 摘要。主卡内不得重复同一数值的 used/limit/remaining 文案；只保留主值、descriptor、必要 reset/status 与可验证的系统进度。主卡必须使用系统 `GroupBox`/`Divider`/`ProgressView`，不得加入自绘材质、固定颜色、描边或阴影来模拟 Liquid Glass。

## 统一数据语义禁区

- 不绕过 `ProviderSnapshot` / `QuotaWindow`，也不让 adapter 直接拼接最终 UI 状态来替代结构化数据。
- 不删除或模糊 source 语义：`Official`、`Official · Estimated`、`Official · Local`、`Experimental`、`Manual check` 必须保留在 snapshot 与无障碍语义中。中性空态可隐藏视觉 source；真实实验、推导、手动或风险数据需要判断时，必须用准确且最短的限定词呈现。
- 没有可信数据时只用主值显示 `No data` 类空态，不再追加重复 source/freshness 提示；不得用计划上限、默认值、旧 mock、历史值或空响应伪造当前 remaining。
- 不把 no-data snapshot 标成 fresh。Freshness 必须基于真实数据与真实 `observedAt`；未来时间、过期文件和没有新 Claude 窗口的事件不能续命旧数据。
- 不钳制原始 negative remaining，也不丢弃 used > limit / used percentage > 100 的超额事实；只有 percentage 已知或 numerator/positive denominator 均可验证时才能显示进度。未知 denominator、limit-only 或普通 KPI 不得显示伪造的 `0%`；只允许最终进度条视觉 fraction 限制在 `0...1`。
- 不把推导值显示成官方直接余额。Google Cloud quota 必须保持 `Official · Estimated`，Google consumer manual 必须保持 `Manual check`。

## 网络与 endpoint 禁区

- 四个 native provider 的远端请求必须经过 Dashis `ProviderHTTPClient` 与 `ProviderEndpointPolicy`；不得回退到 `URLSession.shared` 或为方便而放宽全局 host/path/query/body 验证。collector route 运行在 Worker 中并使用 pinned CodexBar Core 自己的客户端，不能误称为已受 Dashis endpoint allowlist 逐请求代理。
- 保持 ephemeral、no-cache、no-cookie、no-credential-store、8 MiB response cap 和 redirect 拒绝。OAuth/token POST 不自动重试；只有幂等 GET/HEAD 可在既有限制内重试一次。
- 不允许非 HTTPS provider endpoint、非标准 HTTPS 端口、lookalike/subdomain host、embedded user/password、fragment、trailing slash、路径穿越、重复/未知 query 或未允许 body 字段。
- 当前远端 allowlist 只能覆盖：
  - Codex personal：`GET https://chatgpt.com/backend-api/wham/usage` 与 `.../rate-limit-reset-credits`。
  - Codex Enterprise：`GET https://api.chatgpt.com/v1/analytics/codex/workspaces/{workspace}/usage` 及受限分页/时间 query。
  - OpenRouter：`GET /api/v1/key`、`GET /credits`、`GET /activity`、`GET /analytics/meta`、`POST /analytics/query`、可选 `GET /generation?id=...`、OAuth `POST /auth/keys`。
  - Google OAuth token：`POST https://oauth2.googleapis.com/token`，body 不得包含 client secret。
  - Google Cloud Quotas：`GET https://cloudquotas.googleapis.com/v1/projects/{project}/locations/global/services/generativelanguage.googleapis.com/quotaInfos`。
  - Google Monitoring：`GET https://monitoring.googleapis.com/v3/projects/{project}/timeSeries`，filter 只能是受支持的 `generativelanguage.googleapis.com/quota/.../{limit,usage}` metric。
- 新 endpoint、method、query、scope 或 redirect 行为必须先有官方契约、安全评审、allowlist 测试和文档同步；不得只在 adapter 中拼 URL 绕过 policy。
- 错误信息和诊断不得包含 Authorization、Bearer、key、OAuth code/state/verifier、账号 ID、完整请求/响应 body 或 provider 私有字段。
- CodexBar Core 已进入独立 XPC Worker，41 条 live explicit route 已接入 30 个 collector provider，但这不代表 Core 网络已被 Dashis allowlist sandbox。每条 route 必须保持 exact source/strategy/manifest/pin/revision 与 observed-effect 风险摘要；任何新增或变化都要重新审查。不得把 reverse configuration broker 描述成 host HTTP、文件、Keychain、浏览器或 subprocess broker。

## CodexBar/XPC 接线禁区

- App 与 Worker 之间只能使用 `DashisCollectorContract` 的 wire-v4 Data envelope；不得跨 XPC 传 Core 对象、任意 NSSecureCoding object graph、credential handle 内容或原始 HTTP/HTML/body。request/response cap 必须保持 256 KiB/2 MiB，日期保持 Unix 毫秒，budget 保持 1–120000 ms。
- release route 必须使用显式 source；`.auto`、未知 provider/source/strategy、缺失或不匹配的 upstream pin、route-manifest digest、live catalog revision 或 manifest-set digest 必须 fail closed。route digest 不得被误称为完整 effect manifest。
- production Worker 必须保持 single-flight、重复 request-ID 拒绝和净化错误。当前事实是 30 个 collector provider、41 条 live explicit route；不得通过测试开关、隐藏配置、环境变量或 App 参数扩大 route 集合、改选未声明 strategy，或绕过 exact authorization。
- `CollectorRolloutCatalog` 当前 revision 必须保持 34 个唯一 provider、52 条唯一 pinned strategy 和 50 条非 `.auto` binding；`CollectorLiveRouteCatalog` 必须保持排除四个 native provider 重叠路径后的 30 个 provider、41 条 route。wire-v4 handshake 必须在 App/Worker 两侧核对 live route count、revision 与 manifest-set digest；rollout inventory 不得直接替代 live authorization catalog。
- `opencodego.local`、`kimi.cli`、`mimo.local` 当前只能经 upstream `.auto` planner 进入；不得为追求数量给它们伪造 `.cli`/`.api`/`.web` source。上游未提供 exact source binding 前必须保持不可路由。
- `ProviderObservation` 是后台 canonical fact model；collector 成功结果必须先经过 outcome validator，再由 `ProviderObservationSnapshotProjection` 写入现有 `[ProviderID: ProviderSnapshot]`。启动 App、浏览 Dashboard/Sidebar、打开 provider 展示页、进入 Settings 或只选择二级 provider 都不得自动调用 runtime/XPC；只有用户在 Settings 中点击 `Check Usage` 才能执行一次所选 exact route。
- `ProviderCollectionRuntime` 初始化不得发起 XPC、网络、HOME、Keychain、浏览器、CLI 或 Core probe；验证 wiring 必须由显式调用触发。
- XPC connection invalidation 本身不是进程树硬终止。当前 Worker 另有 operation deadline：cooperative cancel、`collector.shutdown()`、2 秒 grace，以及 Worker 自有 process-group `SIGKILL` + `_exit(124)` 兜底；不得删除或弱化。该机制仍未证明能捕获所有自行脱离 process group 的后代，不能描述为完整进程树 sandbox，正式发布仍需补齐 PID/签名与 detached-child 验证。
- Worker 是进程隔离，不是完整 OS sandbox。当前 App Sandbox 关闭；不得以 XPC 或“不进 App Store”为理由降低 endpoint、credential、文件、浏览器、Keychain、subprocess 与潜在费用审查。
- 非 App Store release 必须让 App、Worker 与辅助 executable 使用同一 Developer ID、Hardened Runtime 和 notarization，并校验固定 bundle 路径、签名、Team ID 与版本；不得从 `$PATH`、任意用户目录或下载目录替换 Worker/Core。

- Worker 必须为每次已授权 operation 新建只含一个 request rule、一个 planning rule 和一个 exact strategy rule 的 policy；其它 provider/source/strategy 必须继续 deny。不得用宽泛 `auto`、strategy kind 或跨请求复用 policy 代替 exact route 审查。
- planning policy 必须在上游 resolver 前执行；strategy policy 必须在 `strategy.isAvailable` 与 `strategy.fetch` 前执行。被拒绝的 phase 不得继续触发其后的 Keychain、浏览器、HOME 文件、CLI 或网络 probe。
- strategy kind 不得作为权限事实。当前逐操作 planning 与 strategy policy 必须保守要求完整 capability envelope；任何收窄都必须有 provider/source/runtime/strategy/credits/optional-usage 级源码证据和离线回归。
- fetch 返回的 strategy ID/kind 必须与通过 exact policy 的顶层 strategy 完全一致；不一致必须 fail closed，不得用已授权 attempt 包装未授权 provenance。已授权 strategy 内部调用的 adapter 仍属于 opaque effect，不能声称已有递归 gate。
- `CollectorOutcome` 必须保留 requested/resolved source、strategy/attempt、account resolution、raw percentage、window/reset、placeholder/usageKnown、confidence、credits、component timestamps、live-only artifacts、dashboard 与 sanitized diagnostics；不得把 Core 的 clamp 值反向覆盖 raw `100 - usedPercent`，也不得用较新的 credits/cost 时间给旧 usage 续命。
- App 提供的 collector 临时配置必须只存在于 Store 内存，并通过 connection-scoped、request/route/lease 绑定的 reverse broker 释放一次；只允许所选 route 声明的键，broker 消费后必须移除值。不得写入文件、UserDefaults、Keychain、日志、fixture 或文档；`Clear Session Data` 必须清除 route 输入、observation 和 snapshot，并失效 generation。
- Worker 启动时必须清除除显式 runtime/test-safety allowlist 外的全部继承环境；route 配置只能通过一次性 broker lease 临时安装到 facade context 与真实 process environment，结束后恢复。不得改回“只过滤 facade 字典”或让其它 provider ambient 变量留在 Worker，也不得主动启用 verbose/HTML dump 或持久 CLI session。即使如此，HOME 下硬编码 storage、login-shell rc、浏览器、Keychain、网络与 detached subprocess 访问仍不属于完整 sandbox。
- selected account 必须有稳定 UUID，并由 host resolver 返回匹配确认 ID 与带非空 email/provider account-ID anchor 的 exact identity expectation；其完整 environment/settings 必须替换而不是合并 ambient credential context。label 不得参与凭据选择，未确认账户不得进入 strategy resolution；account-less manual-token callback 不得用于 selected account，token-account writeback 只允许匹配 confirmed UUID。
- selected-account fetch 后必须同时校验 usage identity 与同包 dashboard email；证据不足、provider/账户不匹配或多来源冲突时必须整包拒绝、停止 fallback，且不得暴露 usage、credits、artifact、diagnostic 或 credential ownership。只有验证通过的成功结果可标为 `.resultVerified`；`.hostResolved` 只表示 host 输入 context 已确认。该校验是 post-fetch 防误归因 gate，不是读取/副作用沙箱。
- reverse configuration broker 只能保证 App 主动提供的值按 route/operation 受限，不能声称 Core 没有内部读取或写回。OAuth refresh、provider credential mutation、browser/Keychain prompt、CLI subprocess、本地数据库/日志读取与潜在 billable probe 必须继续逐 strategy 审查。
- 标记 `requiresConsent` 的高风险 route 必须在每次 `Check Usage` 前由 UI 单独确认，并把本次 consent 写入 authorization；Worker 也必须复核。上一次同意、选择 method、打开纯展示页或只在 Settings 选择 provider 都不能替代本次确认。
- CodexBar 的 MIT 许可证不授予 provider private API、Cookie/session 或账号数据使用权；private web/cookie 来源不得因 CodexBar 用户量而自动标成 Dashis `Official`。
- 自动测试不得执行真实 CodexBar provider。只允许 synthetic snapshot、synthetic exact live route、fake/default-deny 路径与临时 scratch；不得读取真实 HOME、Keychain、浏览器、provider CLI 或网络。

## 凭据与隐私禁区

- 不读取、打印、摘要、复制、发送或写入 `.env`、API key、token、password、Cookie、session、私钥、证书、SSH key、Keychain 内容、浏览器 profile 或无关私人文件。
- 不把真实 API 响应、用户数据、账号标识、完整日志、请求体、prompt、completion、成本账单或个人隐私路径写入 docs、report、fixture、截图或 Git。
- collector 临时配置、OpenRouter OAuth key/management key、Google access token、Codex Enterprise analytics key 和 OAuth/PKCE 中间值只存在于当前 App session；不得写入 UserDefaults、文件、日志、Keychain 或 analytics。
- 当前 Google OAuth 必须丢弃 refresh token 与 ID token；若未来需要跨启动登录，必须单独评审 Keychain access、撤销、迁移和删除验证。
- `Clear` 必须取消对应 provider 的本地异步操作与 loopback listener，递增 generation，并清除输入、session key/token、OAuth state/verifier 和内存 snapshot；迟到响应不得重新写回。
- `Clear` 只保证清理 Dashis 本地状态，不能保证撤销已在 OpenRouter 服务端通过 `/auth/keys` 创建的 key。默认界面不常驻这段说明，但执行 `Clear local session` 时必须在确认框中提示用户必要时到 OpenRouter 官方账户页 revoke。

## Codex 禁区

- `~/.codex/auth.json` 只能在用户点击 personal check 后读取，且必须保持普通文件、`O_NOFOLLOW`、当前 UID、私有权限和大小上限校验；测试、文档和日志不得读取或输出其内容。
- Codex personal `wham` 必须标为 experimental/private；不得写成公开官方 API 或保证长期兼容。
- 不把 Codex 查询改成重置、兑换、刷新登录、写 auth、触发任务、导出 prompt/response 或其它有副作用的操作。
- personal usage 与 reset credits 必须保留独立 partial failure；一个请求失败时不得丢掉另一个已验证结果。
- 不得按 `primary_window` / `secondary_window`、plan 名或历史产品规则硬编码 5 小时、周限制或其它固定周期；只展示响应实际给出的窗口，缺失时不显示窗口行，也不追加“未报告固定窗口”提示。
- `credits.balance`、`credits.unlimited`、`credits.has_credits` 只能按响应原值投影；不得把一个账户的 unlimited 状态推广成所有计划都无限制，也不得反向声称所有计划都有固定窗口。
- 账户 credits 与 `/rate-limit-reset-credits` 返回的 available reset credits 必须分开命名和展示，不得把 reset credit 数量伪装成通用消费余额或已执行 reset 次数。
- Enterprise Analytics 必须保持 workspace scope 和受限分页；不得把组织 usage 冒充个人剩余额度。

## Claude 禁区

- Claude Connect 只能由显式的两步操作完成：`Preview connect` 读取 settings 并显示 patch，`Apply change` 才可修改 `~/.claude/settings.json`。
- `Preview connect` 只能验证 bundled helper、读取安全 settings 并生成预览，不得安装 helper 或写 settings；`Apply change` 才能安装 helper并写入经过 fingerprint 复核的 patch，Cancel 必须保持无持久改动。
- settings patch 必须保留原顶层 JSON 其余字节与权限、检测 duplicate key、拒绝 symlink/非当前 UID/不安全权限，并在 Apply 前复核 fingerprint，防止覆盖并发修改。
- 已有支持的 statusLine command 必须链式保留；helper 必须向原命令传递完全相同的 stdin，并转发 stdout、stderr 和退出状态。不得静默覆盖用户原 statusLine。
- helper 只能保存 schema version、`observedAt`、5-hour/7-day `used_percentage` 与 `resets_at`；不得保存 cwd、session ID、transcript、repo、model、cost、email、auth 或原始 statusLine JSON。
- 净化 snapshot 必须保持普通文件、当前 UID、私有目录/0600 权限、8 KiB 上限、原子写入与 schema 校验；不安全文件不得被读取、覆盖或删除。
- 缺少 `rate_limits` 不得清空旧 snapshot；相同窗口不得更新采集时间。Dashis 不得为刷新 quota 自动发送 Claude 请求。
- `Preview disconnect` + `Apply change` 必须恢复原 statusLine 并清除安全 snapshot；`Clear loaded data` 只清 snapshot，不能偷偷解除 bridge。

## Google AI 禁区

- Consumer subscription 没有受支持的第三方余额 API 时，只提供官方页面、Antigravity `/credits` 人工指引和可选 manual snapshot；不得抓 Gemini/Antigravity DOM、Cookie、TUI、private endpoint、内部 OAuth 文件或 Keychain。
- manual reading 必须带用户触发的采集时间与 `Manual check` source；不得自动刷新或冒充实时数据。
- Gemini project 当前必须由用户手工输入 project ID/number；不得声称 Dashis 已列举或发现可用项目。
- 可选 quota ID 必须使用 Cloud Quotas 返回的 exact `quotaId`；输入支持逗号/空白分隔。留空自动选择必须保持最多 24 个 definition 的上限，避免无界 Monitoring fan-out。
- Google OAuth 使用默认浏览器、随机 `127.0.0.1` port/path、PKCE S256、state 和唯一 `cloud-platform` scope；不能改成 `localhost`、宽松 callback 或复用浏览器登录态。
- Project quota 依赖调用者具备 `cloudquotas.quotas.get` 与 `monitoring.timeSeries.list` 权限；权限不足时显示净化错误，不得扩大 scope 或读取其它项目数据。
- quota derivation 必须按 quota ID、`limit_name`、声明 dimensions/model/location、metric type 与 cadence 精确匹配。更具体的 dimension series 不能重复计入默认 bucket；limit 冲突时 remaining unavailable。
- DELTA 才能按匹配窗口求和；concurrent usage 只接受 GAUGE 最新值；未知 cadence、CUMULATIVE 或不匹配数据不能计算 remaining。
- RPD 继续使用 `America/Los_Angeles` 日历午夜；UI 必须保留 Monitoring 约 150 秒延迟警告。

## OpenRouter 禁区

- OAuth 授权 URL 必须遵循 OpenRouter 官方参数：`callback_url`、`code_challenge`、`code_challenge_method=S256`。官方契约没有 `state`；不得伪造 state 兼容性声明。
- 因无 state，必须保留高熵随机 callback path、只绑定 `127.0.0.1`、精确 callback path、一次性 listener 和 PKCE verifier；这些防护不能降级。
- 普通 OAuth key 与 management key 权限/数据范围必须分开。产品默认 `Account` 模式可以显式要求 session-only management key，因为账户级余额/activity/analytics 是当前目标；UI 必须标明 credential 类型和 session 生命周期，且 Dashis 不得 allowlist 或调用 `/api/v1/keys` 创建、更新、禁用、删除等管理写接口。
- `Account` 查询不得默认添加 `api_key_hash`、`user_id` 或其它单-key/单成员过滤；`/activity` 必须明确为聚合数据，不能冒充逐调用日志。
- Recent calls 只能用账户级 analytics 的 `generation_id` 加最多一个 `api_key_id`/model dimension，必须带 hour/day granularity、显式时间范围、`group_limit: 1` 且不带 filters。当前 UI 窗口上限为 30 天、limit 为 20；policy 必须继续限制 generation 查询最多 2 个 dimensions、31 天窗口和 50 行，并拒绝缺失/放宽的 generation `group_limit`。结果只允许 metadata，`metadata.truncated` 必须显示，不得称为完整/全部/最新日志。
- 不得调用 `/generation/content` 或默认读取 prompt/completion。若未来需要内容，必须先取得用户明确授权并单独评审 logging/ZDR、展示、缓存与清除边界。
- negative `limit_remaining` 或 `total_credits - total_usage` 必须保留，不得 `max(0, ...)`。
- total tokens 优先 provider `total_tokens`，缺失时只用 prompt + completion；reasoning 是 completion/output breakdown，不能再加一次。
- 不把不同 activity row、日期、model 或 endpoint 的 rate 指标相加成账户总 rate；只能汇总定义为可加总的 count/token/usage。
- analytics 必须先读取 `/analytics/meta` 并排除 `is_rate` metric；不得永久硬编码不存在的 metric/dimension。账户汇总 analytics 在 `metadata.truncated == true` 时自动缩小窗口重试一次，并明确标注较窄口径或仍不完整状态；recent-call sidecar 不得隐藏其截断状态。
- credits、activity、analytics、generation 必须保留独立 partial failure；一个子请求失败不能抹掉其它有效数据。

## 测试与文档禁区

- 自动测试只使用合成 fixture，且必须离线；不得读取真实 `~/.codex`、`~/.claude`、App Support snapshot、浏览器、Keychain 或真实 provider 账户。
- Debug `--visual-qa` 只能注入仓库内定义的合成 snapshot 并用于视觉 QA；fixture 初始化不得读取账户文件、credential、完整响应或自动触发 provider 网络检查。Release 不得启用该 fixture，也不得把它的合成值冒充真实账户状态。
- endpoint policy、decoder fail-closed、negative remaining、OAuth callback、Claude snapshot/settings 恢复、Google derivation 与 stale/freshness 保护不得无测试降级。
- 任何影响启动/构建、Run action、UI 流程、provider 接入、凭据生命周期、endpoint allowlist、验证或排障的修改，必须同步更新 `docs/USER_TUTORIAL.md`。
- `docs/NEXT_TARGET.md` 只记录一个 active target；目标完成或失效后删除，长期事实迁移到其它项目文档。
