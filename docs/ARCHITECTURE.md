# ARCHITECTURE

## 当前产品边界

Dashis 当前是 macOS 原生 SwiftUI、provider-first 的 AI 用量 dashboard，不使用 `WKWebView`、Web dashboard、Node gateway 或 localhost 业务服务。

- Xcode 工程包含三个 target：macOS App `Dashis`、命令行 helper `ClaudeStatusLineHelper`、测试 target `DashisTests`。
- shared scheme `Dashis` 构建 App 与 helper，并在 Test action 运行 `DashisTests`。
- Dashboard 固定展示 Codex、Claude、Google AI、OpenRouter 四个内置 provider；Sidebar 只提供 Dashboard 与四个 provider 路由，不提供说明型 Settings 或动态 Add provider。
- `script/build_and_run.sh` 是本地 build/run 入口；`.codex/environments/environment.toml` 的 Run action 调用同一脚本。
- 当前没有 iOS target、后端、数据库、长期凭据存储或部署配置；这些边界仍为 `UNKNOWN`。

## 目标分层

```text
DashisApp / DashboardView
  -> DashisProviderStore
       UI state / session-only inputs / explicit user actions
       generation guards / Clear / snapshot-to-summary/detail projection
  -> DashisProviderService
       composition root only
       -> CodexUsageClient
       -> ClaudeUsageClient
       -> GoogleConsumerUsageClient
       -> GeminiAPIProjectUsageClient
       -> OpenRouterUsageClient
       -> Google ProviderConnectionCoordinator
       -> OpenRouter ProviderConnectionCoordinator

Shared provider foundation
  -> ProviderSnapshot / QuotaWindow / ProviderBalance / ProviderMetric
  -> ProviderCardProjection / FreshnessPolicy
  -> ProviderJSON
  -> ProviderHTTPClient -> ProviderEndpointPolicy
  -> LoopbackOAuthCoordinator / ProviderOAuthSupport
```

`DashisProviderService` 不解析 provider 响应、不持久化凭据，也不定义 endpoint；它只组装 adapter 和连接协调器。各 adapter 先生成结构化 `ProviderSnapshot`，Store 再统一投影 Dashboard 摘要。provider detail 直接从 snapshot 生成类型化 `ProviderVisualization` / `ProviderUsageCard`，避免解析旧 key/value 文案或把 UI 文案当成数据模型。

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

OpenRouter 有默认 OAuth key mode 与 Advanced management key mode。

默认 OAuth：

```text
用户点击 Connect OpenRouter
  -> 默认浏览器打开 https://openrouter.ai/auth
  -> 随机 127.0.0.1 port + 随机一次性 callback path
  -> PKCE S256（OpenRouter 官方 OAuth 契约没有 state 参数）
  -> POST /api/v1/auth/keys 换取用户控制的 API key
  -> session-only key
  -> GET /api/v1/key
  -> officialDirect key limit / usage / limit_remaining
```

OpenRouter 官方 OAuth 授权 URL 没有定义 `state`，因此实现不伪造 provider 未接受的 state；callback 的隔离依赖高熵随机 path、只绑定 `127.0.0.1`、精确 path 校验、一次性 listener 与 PKCE verifier。Google OAuth 仍使用并严格校验 state。

Advanced management：

- session-only management key 并发查询 `/api/v1/credits`、`/api/v1/activity`、`/api/v1/analytics/meta`、`/api/v1/analytics/query` 和可选 `/api/v1/generation?id=...`。
- analytics 先读取 meta，只选择实际可用且 `is_rate == false` 的可加总 metric/dimension；`metadata.truncated` 时自动缩小时间窗一半重试一次，并明确显示较窄口径或仍不完整警告。
- 每个子请求保留独立 partial failure，不因一个失败抹掉其它有效结果。
- rate/token metric 分别保留 provider 返回的意义；不得把不同日期、模型或 endpoint 的 rate 相加成一个伪造速率。
- total token 优先 provider 的 `total_tokens`，缺失时使用 prompt + completion；reasoning 只作 output breakdown，不再次相加。

`Clear` 会取消本地 listener/task 并清除 app 内的 key、verifier、输入与 snapshot，但无法保证撤销已经由 `/auth/keys` 在 OpenRouter 服务端创建的 key。若授权完成后状态不确定，用户必须在 OpenRouter 官方账户页面撤销该 key。

## OAuth 与网络安全边界

- OAuth 使用系统默认浏览器，由 `NSWorkspace` 打开 provider 授权 URL；不是 `ASWebAuthenticationSession`。
- loopback listener 只绑定随机 `127.0.0.1` 端口，callback path 含随机 nonce；不绑定 `localhost`、IPv6 或外部接口。
- Google 和 OpenRouter 分别使用独立 `ProviderConnectionCoordinator`；Clear 一个 provider 不应取消另一个 provider 的连接。
- 所有远端数据请求经 `ProviderHTTPClient`；配置为 ephemeral、无 cache、无 cookie、无 credential store，响应上限 8 MiB。
- 远端 redirect 一律拒绝；POST token/code exchange 不重试，只有 GET/HEAD 可对有限的 429/502/503/504 或瞬时网络错误重试一次。
- `ProviderEndpointPolicy` 校验 HTTPS、标准端口、精确 host/path/method/query/body schema，并拒绝 embedded credentials、fragment、trailing slash 与未允许字段。
- 错误只进入净化摘要；不显示 Authorization、key、code、verifier、完整请求/响应或账号标识。

## 状态生命周期

所有远端检查由用户显式动作触发。Store 使用每-provider generation 和 operation ID：切换 mode、Clear 或开始新动作后，旧异步响应不能重新写回 UI。Google access token、OpenRouter OAuth key/management key、Codex Enterprise analytics key 与 PKCE/OAuth 中间状态只存在于当前 App session。

Claude 是唯一允许事件驱动写入本地净化 snapshot 的 bridge；该文件只含白名单 quota 字段，不是凭据或完整 provider 响应。当前没有 refresh token 或 API key 的跨启动持久化；未来若引入 Keychain，必须作为独立凭据政策变更评审。

## UI 与设计边界

- Sidebar 固定为 Dashboard、Codex、Claude、Google AI、OpenRouter；没有说明型 Settings 或 Add provider。
- UI 调整必须保留旧版 Dashis 外壳而不是重写：品牌 28 pt serif、页标题 32 pt serif、Sidebar min 176 / ideal 218、导航约 14 pt serif 且行距约 40 pt、选中态为低对比浅蓝；详情容器使用 14 pt 纵向 spacing 与 horizontal 30 / top 26 / bottom 30 外边距，provider 内容最大宽度 900，外层最大宽度 1180。
- Dashboard 用带分隔线的扁平列表展示四条摘要；空态每条只保留 provider 名称、主值和一个动作，不显示 kind、source/freshness、辅助统计或解释小字，也不把四条摘要包装成卡片墙。
- 有真实数据或风险时只增加一个必要限定词：`Experimental`、`Estimated`、`Manual`、`Historical`、`Stale`、`Expired`、失败/超额或 warning；正常状态不额外占行。
- provider route 无 snapshot 时直接显示主操作，不显示占位明细、默认帮助段落或无状态可清的 Clear；有本地状态后才出现对应 Clear。有 snapshot 时，返回的主要 quota/balance（或没有 quota 时的主 KPI）以两列低噪声卡片呈现。当前 App 最小布局支持两列；只有未来布局约束确实不足时才允许降为一列。
- 主卡片内部只保留 label、主要数值/descriptor、可验证进度与必要 reset/status。额外 quota/metric 与 source/scope/observed metadata 分别放进默认折叠的 disclosure；warning 与 partial failure 不套额外卡片，在主卡片下各完整展示一次。
- 同一屏内不通过 primary、caption、stats、progress 和 raw lines 重复表达同一份 snapshot 数据；类型化 projection 是 detail 的唯一数值布局入口，高级配置继续留在用户主动展开的 disclosure 中。
- 主题保持 macOS 系统白/黑，语义色只表达 connected/watch/incident；Dashis 品牌、页标题与主数值保留原有 macOS system serif，正文、控件和辅助信息使用 system sans，只有代码/日志类内容使用 monospace。
- Codex Analytics 网页的用途仅限于校准 quota/balance 的信息优先级、进度表达与去重；它不能成为替换 Dashis 字体、Sidebar、字号、位置、间距或品牌身份的整页重写依据。
- 不重新引入装饰性品牌块、subtitle 堆叠、Recent monitors、timeline、旧 Models/Runs/Alerts、首页小指标网格或 inspector-first 布局。

### Debug 视觉 fixture

Debug 构建接受 `--visual-qa` launch argument。它只向 Store 注入一份固定、合成的 Codex snapshot 并将路由切到 Codex detail，用于截图、两列卡片、进度和层级的视觉回归；fixture 初始化不读取 `~/.codex/auth.json`、其它账户文件、credential 或真实 provider response，也不自动发起网络请求。该路径不属于产品数据源，Release 构建不启用，不能用于证明真实 provider correctness。

## 未确认架构

- iOS target、跨 Apple 平台共享代码与移动端 OAuth/Claude bridge：`UNKNOWN`。
- 后端/BFF、数据库、通知、定时刷新、长期历史与 dashboard 业务 KPI：`UNKNOWN`。
- OpenRouter/Google refresh token 是否可持久化到 Keychain：未批准；当前明确不持久化。
- Google consumer 若未来发布官方第三方余额 API、Codex personal 若未来发布公开 quota API：需要重新研究和安全评审，不能自动沿用当前 manual/private 路径。
