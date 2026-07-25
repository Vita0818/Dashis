# Dashis 使用教程

本文面向在本机运行和验收 Dashis 的用户。Dashis 当前是 macOS 原生 SwiftUI dashboard，不是网页、WebView 或 localhost gateway 包装。

## 现在能做什么

Dashis 固定提供四个 provider：

| Provider | 当前模式 | 数据性质 |
|---|---|---|
| Codex | Personal desktop；Enterprise workspace analytics | Personal 为非公开实验接口；Enterprise 为官方 workspace usage |
| Claude | Claude Code statusLine 本地 bridge | 官方本地字段的净化 snapshot |
| Google AI | Consumer subscription；Gemini API project | Consumer 人工查看；Project 由官方 Cloud API 推导 |
| OpenRouter | Account；Single key | 默认读取账户级 credits/activity/analytics；可选查看单 key limit |

当前不能动态 Add provider，也没有无实际偏好项的说明型 Settings 页面。iOS、后端、长期历史、通知、自动定时刷新和跨启动凭据仍未实现。

## 先理解 source 与 freshness

Dashis 始终在数据模型中保留来源。默认空态不再重复显示 source/freshness 小字；当真实结果、推导/手动/实验来源或风险需要判断时，界面才显示一个最短限定词：

- `Official`：官方接口直接返回。
- `Official · Estimated`：用官方 limit 与 usage 严格匹配后推导。
- `Official · Local`：Claude Code 官方 statusLine 通过本地 bridge 提供。
- `Experimental`：Codex personal 的非公开只读 endpoint，可能随时变化。
- `Manual check`：没有受支持的第三方机器接口，由用户人工查看或录入。

正常 freshness 不常驻显示；`Historical`、`Stale`、`Expired`、warning 与 failure 会显式出现。没有可信数据时只用主值表达空态，不会生成一个看似实时的百分比；若 remaining 为负数，Dashis 会如实显示超额。

进度条也不会用未知值补 `0%`。只有 provider 直接返回 percentage，或 used/remaining 与正 limit 能组成可靠分母时才显示；limit-only、未知 denominator 和普通 workspace KPI 只显示数值。

## 启动 Dashis

在项目根目录运行：

```sh
./script/build_and_run.sh
```

需要同时确认 App 已启动并保持运行时：

```sh
./script/build_and_run.sh --verify
```

脚本会停止旧的 Dashis 进程，构建 macOS Debug App，准备生成 bundle 的 xattr，再通过 LaunchServices 打开。构建使用 `ENABLE_DEBUG_DYLIB=NO`，避免临时 App 依赖 Xcode debug dylib/stub executor。Codex App 中的 Run action 调用同一脚本。

开发者需要只看合成数据的视觉回归时，可先按 `docs/TESTING.md` 构建，再用 `--visual-qa` 打开 Debug App。该 fixture 只注入合成 Codex snapshot 并进入 Codex detail；初始化不读取账户文件、credential 或真实响应，也不自动检查 provider。它不在 Release 生效，也不能替代真实 provider 验收。

## 界面导览

启动后应看到：

- Sidebar：Dashboard、Codex、Claude、Google AI、OpenRouter；没有 Settings 或 Add provider。它保留旧版 Dashis 的 28 pt serif 品牌、约 14 pt serif 导航、约 40 pt 行距与浅蓝选中态，列宽为 min 176 / ideal 218。
- 页面外壳：页标题保持 32 pt serif；详情区使用 horizontal 30 / top 26 / bottom 30 外边距和 14 pt 纵向 spacing，provider 内容最大宽度 900，外层最大宽度 1180。这些尺寸和位置是旧版外壳约束，不应随卡片内容调整被整体重写。
- Dashboard：带分隔线的四 provider 扁平列表；空态每条只显示名称、主值和一个主动作，真实来源风险或异常才增加一个短限定词；不显示辅助统计、正常状态小字、旧 mock telemetry、runs 或 Web 内容，也不把首页做成卡片墙。
- Provider detail：无数据时只显示主操作，不放占位明细、帮助段落或无状态可清的 Clear；本地状态产生后 Clear 才出现。有数据时，主要 quota/balance 或 KPI 用两列卡片显示主数值、必要 descriptor、可验证进度和 reset/status。当前 App 最小布局仍支持两列；只有未来布局约束不足时才允许一列。
- Secondary detail：额外 quota/metric 与 source/scope/observed metadata 默认折叠；warning 与 partial failure 不套额外卡片，各完整显示一次。界面不再把 snapshot 展开成一长张 raw key/value 表。

Dashboard 摘要上的主按钮会执行当前 mode 的主要动作；完整数据、配置和清理按钮只在 provider detail 展示。

Codex Analytics 网页只用于参考 quota/balance 的信息层级、进度表达与内容去重，不代表 Dashis 要照搬其字体、Sidebar、字号、位置或品牌样式。

## Codex

### Personal desktop usage

1. 确认当前 macOS 用户已经在 Codex Desktop/CLI 使用同一套本地登录材料。
2. 打开左侧 `Codex`。
3. 点击 `Check desktop usage`。

只有点击后，Dashis 才会安全读取本机 `~/.codex/auth.json` 并访问两个只读 endpoint：

```text
https://chatgpt.com/backend-api/wham/usage
https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
```

这两个 endpoint 不是公开稳定的 Codex quota API，因此 UI 标为 `Experimental`。usage 与 available reset credits 是独立请求；其中一个失败时，另一个已验证结果仍应显示，并列出 partial failure。Dashis 不会刷新登录、写 auth、重置额度或触发 Codex 任务。

当前 Codex 额度按账户计划、共享 agentic credits/用量池和服务端实时返回状态决定。Dashis 不再预设“Codex personal = 5 小时窗口”，也不会把 `primary_window` 字段名解释成五小时：

- 若 usage 返回 `credits.balance`，摘要显示实际 credit 数值。
- 若当前账户明确返回 `credits.unlimited=true`，摘要显示 `Unlimited`；这只描述该次响应对应的账户，不能推广到所有计划。
- 若只返回 `has_credits`，显示 `Available` 或 `No additional credits`。
- 只有响应实际包含 usage window 时才显示窗口；标题按它返回的 duration 生成。没有窗口时不显示窗口行，也不补提示或默认周期。
- `/rate-limit-reset-credits` 的数量显示为 `Available reset credits`，与账户的通用 Codex credits 分开。

OpenAI 官方说明当前 Codex、ChatGPT Work、ChatGPT for Excel 和 Workspace Agents 共享 agentic usage/credit pool，实际消耗取决于任务大小、复杂度、模型和运行位置；最终状态仍以当前账户的官方 usage page/limit banner 为准。参考 [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan/) 与 [Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card-2)。

若本地 auth 不存在、是 symlink、所有者/权限不安全、过大或格式不支持，界面只显示净化错误，不显示文件内容或 token。

### Enterprise workspace analytics

在同一页面展开 `Workspace analytics` 后输入：

- `workspace id`。
- 具有 `codex.enterprise.analytics.read` scope 的 analytics API key。
- 1–90 天的 Analytics window。

点击 `Check workspace analytics`。Dashis 会分页读取官方 workspace usage，每页最多 500 条、最多 100 页。它展示的是组织 workspace 聚合 activity/turn/token，不是个人订阅 remaining。

Analytics key 只在当前 App 内存中存在。点击 `Clear Codex data` 会清空 Codex 输入与已加载 snapshot；退出 App 后也不会保留。不要把真实 key 写入文档、截图、issue、测试或日志。

## Claude

### 连接本地 bridge

Claude quota 来自 Claude Code 官方 `statusLine.rate_limits`。Dashis 不读取 Claude auth、Cookie、transcript，也不会为了刷新额度自动发送 Claude 请求。

1. 打开左侧 `Claude`。
2. 点击 `Preview connect`。
3. 阅读 `Pending settings change` 摘要。
4. 确认后点击 `Apply change`；不接受则点 `Cancel`。

需要特别理解 Preview 与 Apply 的差别：

- `Preview connect` 只验证 App bundle 中的 `dashis-claude-statusline`、安全读取 `~/.claude/settings.json` 并生成字段级预览；它不安装文件，也不修改 settings。
- `Cancel` 不产生持久改动。
- 只有 `Apply change` 会安装/更新私有 helper、再次校验 settings 是否被并发修改，并原子写入 statusLine 配置。
- 如果用户原本已有受支持的 statusLine command，Dashis 会把它链在 helper 后面，保留同一 stdin、stdout、stderr 与退出状态。

helper 和 snapshot 默认位于：

```text
~/Library/Application Support/com.vitemis.dashis/ClaudeBridge/bin/dashis-claude-statusline
~/Library/Application Support/com.vitemis.dashis/ClaudeBridge/snapshot.json
```

snapshot 只保存 schema version、采集时间，以及 5-hour/7-day 的 used percentage/reset time；不保存 cwd、session、transcript、repo、model、cost、email 或原始 JSON。

### 获取和刷新 Claude 用量

Apply 成功后：

1. 在 Claude Code 中正常产生至少一次模型响应。
2. 回到 Dashis 点击 `Reload snapshot`。

若 Claude Code/订阅提供 `rate_limits`，Dashis 会显示 5-hour 和/或 7-day window，并计算 remaining = 100 - used。一个窗口可能单独缺失；没有 `rate_limits` 的 statusLine 事件不会清除旧值，也不会把旧数据重新标成刚更新。

本地 snapshot 超过 15 分钟显示 stale，超过 24 小时显示 expired。产生新的 Claude Code 响应后再 Reload；Dashis 不会替你发送请求。

### 清除与断开

- `Clear loaded data`：只删除经过安全校验的净化 snapshot，不修改 Claude statusLine；bridge 仍保持连接。
- `Preview disconnect`：只生成恢复预览。
- `Preview disconnect` 后 `Apply change`：恢复连接前的 statusLine（没有旧 command 时移除 Dashis statusLine），并删除安全 snapshot。

如果 settings 在 Preview 与 Apply 之间变化，Apply 会拒绝覆盖；重新 Preview 后再决定。

## Google AI

Google 页面顶部有两个互斥 mode。切换 mode 会取消当前 Google OAuth 操作并清除当前展示的 Google snapshot；必要时需要重新连接/检查。

### Consumer subscription

Google 没有提供让第三方 App 读取 Gemini consumer subscription 剩余量的受支持 API，因此此模式始终是人工流程：

1. 点击 `Open Gemini official page` 在默认浏览器打开 Gemini 官方页面。
2. 若使用 Antigravity CLI，在其终端输入 `/credits` 查看官方 quota/credits。
3. 可选：展开 `Manual reading`，把 `Used`、`Limit`、`Remaining` 与 `Unit` 填入 Dashis。
4. 点击 `Record reading`。

所有数值都可留空；有值时必须是有限数字。若 used + remaining 与 limit 不一致，Dashis 会原样显示并给出警告，不会偷偷修正。manual reading 带当前采集时间，source 始终为 `Manual check`，不会自动更新。

Dashis 不抓 Gemini/Antigravity 网页 DOM、Cookie、browser profile、Keychain、私有 OAuth 文件、TUI 输出或未公开 endpoint。

### Gemini API project

准备条件：

- 在 Google Cloud 项目中启用 Cloud Quotas 与 Cloud Monitoring 所需 API。
- 创建 OAuth client 类型为 Desktop app，并取得 client ID；不要在 Dashis 中输入 client secret。
- 当前授权主体对目标项目具备可执行 `cloudquotas.quotas.get` 与 `monitoring.timeSeries.list` 的 IAM 权限。
- 已知目标 Google Cloud project ID 或 project number。Dashis 当前不会列出项目，必须手工输入。

操作步骤：

1. 切换到 `Gemini API project`。
2. 输入 `Google Desktop OAuth client ID`。
3. 输入 `Google Cloud project ID or number`。
4. 可选：在 `optional quota IDs, comma-separated` 输入一个或多个 Cloud Quotas exact `quotaId`；逗号、空格或换行都可分隔。
5. 点击 `Connect Google`。
6. 在系统默认浏览器完成 Google 授权。
7. Dashis 连接成功后会自动检查一次；之后可点击 `Check quotas` 重查。

quota ID 可从目标项目的 Cloud Quotas 控制台或官方 `quotaInfos.list` 响应中的 `quotaId` 字段取得，不要填 display name。留空时 Dashis 会按受支持 cadence 优先、稳定排序，最多自动选择 24 个 definition；输入 exact ID 可进一步缩小 Monitoring 请求范围。

授权只请求 `https://www.googleapis.com/auth/cloud-platform` scope，使用随机 `127.0.0.1` loopback port/path、PKCE S256 与 state。access token 只在当前 App session 保留；refresh token 和 ID token 被丢弃。浏览器本来已登录只会减少登录步骤，不代表 Dashis 已自动获得授权。

Dashis 从 Cloud Quotas 读取有效 limit，再从 Cloud Monitoring 读取对应 limit/usage series。只有 quota ID、`limit_name`、dimension/model/location、metric type 和窗口可可靠匹配时才计算 remaining；否则显示 unavailable/警告。region/zone 会与 Monitoring 的 exact location label 对齐。minute/hour 会选择最新完整且已可见的历史窗口；摘要把主值明确标为 `historical`，detail 只在对应 window/warning 中给出一次 exact `as of`。它不是当前实时分钟余额。RPD 按 `America/Los_Angeles` 日历午夜重置。

Cloud Monitoring 通常可能延迟约 150 秒，因此刚产生的请求不一定立即出现。Project 结果标为 `Official · Estimated`，不是 provider 直接返回的余额。

Consumer mode 的 `Clear Google data` 或 Project mode 的 `Clear Google session` 会取消 Google 的本地 OAuth listener 和在飞请求，清除 access token、client/project/quota-ID/manual 输入与 snapshot；不会撤销 Google 账户中的其它授权或修改项目 IAM。

## OpenRouter

OpenRouter 页面有 `Account` 与 `Single key` 两个 mode，默认是整个账户视角。切换 mode 会取消当前 OpenRouter OAuth 操作、清除该 provider 的临时 credential 和 snapshot；必要时重新输入 management key 或重新连接 single key。

### 默认 Account

1. 保持 `Account` mode。
2. 若从 Dashboard 开始，点击 `Set up account` 进入 OpenRouter 详情；再点击 `Create a management key in OpenRouter`，在官方页面创建 Management API key。
3. 回到 Dashis，把 key 临时输入 `Management key · session only`。
4. 点击 `Check whole account`。
5. 若要看近期调用，先等账户检查成功，再展开 `Recent calls · metadata only`。
6. 选择 1–30 天窗口并点击 `Load call metadata`。

Account 主卡显示 OpenRouter 账户累计购入 credits、累计消费和 `total_credits - total_usage` 得出的 remaining。它不是某一把普通 API key 的消费上限，也不要求其它程序或后续模型调用改用 Dashis 的 key。

同一次检查还会读取：

- `/activity`：账户最近 30 个已完成 UTC 日的聚合活动，不加 `api_key_hash` 或 `user_id` 过滤。它按日期、endpoint/model/provider 聚合，不是逐调用原始日志。
- `/analytics/meta` + `/analytics/query`：在 `Account analysis options` 指定的 1–90 天窗口内读取账户分析；请求显式带 time range，默认不加单-key filters。
- 可选 `/generation?id=...`：只有你已有 generation ID 时才读取那一次调用的 metadata。Dashis 不读取 prompt/completion 内容。

近期调用区会通过 analytics 的 `generation_id` dimension 读取最多 20 条账户级 metadata 行，并在可用时附带 key/model 标签、时间 bucket、usage/cost 和 token。请求显式使用 `group_limit: 1` 与总 `limit: 20`，避免 OpenRouter 对 time-series 查询自动提高返回行数。它是独立查询：失败不会清掉已经成功显示的账户余额。

OpenRouter 官方目前没有一个带 cursor、可直接列出全部逐调用 generations/logs 的公开 API，因此这个列表不是完整历史，也不保证恰好是“最新 20 条”。同一 ID 会去重，OpenRouter 也可能返回 `truncated`；Dashis 会明确提示，而不会把结果称为全部日志。修改 Call window 会清掉旧列表，需重新点击加载，防止把旧 1 天结果误看成新 30 天结果。Dashis 不请求 prompt/response，也不调用 `/generation/content`。

Management key 本身可以管理账户 key，权限高于普通推理 key，而且不能用于模型 completion。Dashis 只把它保存在当前 App 内存中，并且 endpoint allowlist 不允许 `/api/v1/keys` 的创建、修改、禁用或删除操作。`Clear local session` 会清掉内存中的 management key、输入、snapshot 与 recent-call metadata。

### 可选 Single key

只有想检查某一把普通 key 自己的 limit/usage/remaining 时才切换 `Single key`：

1. 点击 `Connect OpenRouter`。
2. 在系统默认浏览器中确认授权；OpenRouter 会创建/返回一把用户控制的普通 API key，并可能要求设置该 key 的消费上限。
3. 回到 Dashis 查看 `/api/v1/key` 返回的 key-level limit、usage、`limit_remaining`、reset/expiry。

这个金额只是单 key 的消费上限，不是账户余额，也不是从账户划拨出的独立钱包。只有使用这把 key 的模型请求才会增加它自己的 usage；其它程序可以继续使用自己的 OpenRouter key。

Dashis 使用随机 `127.0.0.1` callback port 和一次性随机 path，加上 PKCE S256。OpenRouter 官方 OAuth 授权参数没有 `state`，因此 Dashis 不发送伪造 state；callback 的隔离依赖随机 path、严格本机绑定、一次性 listener、精确 path 校验与 PKCE verifier。OAuth key 只在当前 App session 内存中存在。

Single-key 模式执行 `Clear local session` 时只能清理 Dashis 的 listener/task、key、verifier、输入与 snapshot，不能保证撤销已经在 OpenRouter 服务端创建的 key。如果浏览器端已经批准，而 Dashis 随后取消、崩溃、超时或状态不确定，请到 OpenRouter 官方账户/API keys 页面手工 revoke 对应 key。

### 账户数值规则

Analytics 会先读取 meta，只汇总服务端标为非 rate 的可加总 metric。若结果 `truncated`，Dashis 会自动把时间窗缩小一半重试一次并明确标注较窄口径；若重试仍被截断，UI 保持不完整警告，用户可继续缩短 Analytics window 后重查。

理解数值规则：

- negative remaining 会原样显示，不会被钳成 0。
- token total 优先 provider 的 `total_tokens`；缺失时才使用 prompt + completion。
- reasoning 是 output/completion breakdown，不会再次加进 total。
- 不同日期、模型或 endpoint 的 rate 不会被相加成伪造的账户总 rate。
- credits、activity、analytics、generation 任一失败时，其它成功结果仍会保留，并显示 partial failure。

不要把真实 management key 或普通 key 写入文档、截图、issue、fixture 或日志。

## 凭据与 Clear 的共同规则

- 所有网络检查都来自用户显式点击；Dashis 不做后台定时 provider 请求。
- Codex Enterprise key、OpenRouter key、Google access token、OAuth state/PKCE verifier 都不会写入 UserDefaults、仓库、文档、日志或 Keychain。
- Clear 会使当前 provider 正在执行的旧响应失效，防止它稍后重新填回已清空的 UI。
- Claude 净化 snapshot 是唯一受控的本地用量文件；它不包含凭据，并可由 Clear/Disconnect 删除。
- 遇到错误时只分享净化后的错误类别。不要复制真实 Authorization、账号 ID、完整 request/response 或 provider 页面中的私人数据。

## 手动验收清单

- `./script/build_and_run.sh --verify` 构建并启动成功。
- Sidebar 恰好只有 Dashboard 与固定四 provider，没有 Settings 或 Add provider。
- 对照旧版 Dashis 外壳确认：品牌 28 pt serif、页标题 32 pt serif；Sidebar min 176 / ideal 218、约 14 pt serif 导航、约 40 pt 行距与浅蓝选中态；详情 horizontal 30 / top 26 / bottom 30、spacing 14、provider max width 900、outer max width 1180。不能只恢复字体家族却留下错误的字号或位置。
- Dashboard 没有 WebView、网页、Node gateway、旧 mock telemetry 或 runs。
- Dashboard 是带分隔线的四 provider 扁平列表；中性空态只含名称、主值和动作，没有统计、正常状态小字、重复 caption/progress/明细或逐行套框。
- provider route 无 snapshot 时没有占位行或帮助段落；有 snapshot 时，主要 quota/balance 或 KPI 在两列主卡片中显示，额外指标与 metadata 默认折叠，不出现一长张 raw key/value 表。
- 只有已知 percentage 或可验证 numerator/positive denominator 的卡片显示进度；limit-only、未知 denominator 与普通 KPI 不显示伪造 `0%`。
- warning 与 partial failure 不套额外卡片，各完整显示一次；展开 More usage data / Data details 后不重复主值。
- no-data 摘要只用主值表达空态；真实来源风险与异常限定词和实际路径一致。
- Codex personal 为 Experimental；没有实际窗口时不显示推断的 5-hour/weekly 限制，credits 与 available reset credits 分开；Enterprise 是 workspace usage，不冒充个人 remaining。
- Claude Preview 无持久写入，Apply 才安装 helper并改 settings；已有 statusLine 连接/断开后能恢复。
- Google consumer 只人工查看；Project mode 显示 Estimated 和约 150 秒延迟警告。
- OpenRouter 默认 Account mode 显示账户 remaining 和无单-key过滤的聚合活动；账户成功后可加载 1–30 天、最多 20 条 metadata-only recent calls，截断提示清楚且失败不影响余额。Single key 的 OAuth 取消、拒绝、超时、key 过期都有净化错误，Clear 后必要时能按指引去服务端 revoke。
- 所有 SecureField/session token 在 Clear 或 App 退出后不可复用；日志和 UI 不泄漏凭据/完整响应。
- light/dark 分别是 macOS 系统白/黑；Dashis 品牌、页标题与主数值保持原有 system serif，正文和控件保持 system sans；卡片边框与阴影克制，不恢复玻璃渐变。
- Debug `--visual-qa` 只显示合成 Codex snapshot，不读取账户/credential、不自动联网，Release 不启用。

## 常见问题

### `./script/build_and_run.sh --verify` 失败

查看最近系统日志：

```sh
/usr/bin/log show --style compact --last 2m --predicate 'eventMessage CONTAINS[c] "Dashis" OR eventMessage CONTAINS[c] "com.Vita0818.DashisMac" OR eventMessage CONTAINS[c] "AppleSystemPolicy" OR eventMessage CONTAINS[c] "AMFI"'
```

如果出现 AppleSystemPolicy/AMFI 拒绝，确认脚本仍使用 `ENABLE_DEBUG_DYLIB=NO`，并执行生成 bundle 的 provenance/quarantine xattr 准备。

### Xcode Console 出现 logging timeout

shared scheme 已设置 `IDEPreferLogStreaming=YES`。`Failed to initialize logging system due to time out` 不一定代表 App 崩溃；同时检查 Dashis 进程和系统 crash/AMFI 日志。

### Claude 一直没有数据

- 确认已 Preview 并 Apply，而不是只完成 Preview。
- 确认 Claude Code 版本/订阅会提供 statusLine `rate_limits`。
- Apply 后在 Claude Code 产生一次真实响应，再回 Dashis Reload。
- `Clear loaded data` 不会断开 bridge；如果曾 Disconnect，需要重新 Connect + Apply。

### Google Project 显示权限错误或旧数据

- 检查 project ID/number 是目标项目，不是 display name。
- 检查当前授权主体具备 `cloudquotas.quotas.get` 与 `monitoring.timeSeries.list`。
- 检查相关 API 已启用。
- 等待约 150 秒再重查 Monitoring；仍无法精确匹配时 Dashis 会保持 unavailable，而不会猜测。

### OpenRouter 授权后仍未连接

- 这一节只适用于可选的 `Single key` mode；默认 `Account` mode 不走 OAuth。
- 确认浏览器回调到本机 `127.0.0.1` 没有被代理/防火墙拦截。
- 重新点击 Connect，使用新的随机 callback/PKCE session。
- 如果浏览器已经批准但 App 状态不确定，先到 OpenRouter 官方账户页检查并 revoke 多余 key。

### OpenRouter Account 显示 401/403

- 确认输入的是 OpenRouter `Management API key`，不是普通 API key 或 OAuth 创建的 single key。
- Management key 只在当前 App session 有效；重启或 Clear 后需要重新输入。
- Dashis 不会通过 management key 发送模型请求，也不会创建、修改、禁用或删除账户中的其它 key。

### Codex personal 突然失效

Personal `wham` 是非公开契约，字段和计划返回形态都可能改变。先到 Codex 官方 usage page/limit banner 核对当前账户；不要通过放宽 endpoint、复制 Cookie 或刷新登录来绕过。Dashis 应保留 Experimental/fail-closed 状态，并且在服务端不返回窗口时保持 windowless，而不是补回旧的五小时假设。

## 教程维护规则

任何变更只要影响启动、构建、Run action、Dashboard/sidebar/detail、provider 接入、凭据生命周期、endpoint allowlist、验证或排障，就必须同步更新本文。未更新时必须在最终报告说明原因。
