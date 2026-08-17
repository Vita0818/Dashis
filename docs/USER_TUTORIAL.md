# Dashis 使用教程

本文面向在本机运行和验收 Dashis 的用户。Dashis 当前是 macOS 原生 SwiftUI dashboard，不是网页、WebView 或 localhost gateway 包装。

## 现在能做什么

Dashis 内置固定的 34 个 reviewed provider catalog；默认全部显示，用户可在 Settings 中逐项控制哪些 provider 出现在主 Sidebar 与 Dashboard。其中四个已经有原生可操作流程：

| Provider | 当前模式 | 数据性质 |
|---|---|---|
| Codex | Personal desktop；Enterprise workspace analytics | Personal 为非公开实验接口；Enterprise 为官方 workspace usage |
| Claude | Claude Code statusLine 本地 bridge | 官方本地字段的净化 snapshot |
| Gemini | Consumer subscription；Gemini API project | Consumer 人工查看；Project 由官方 Cloud API 推导 |
| OpenRouter | Account；Single key | 默认读取账户级 credits/activity/analytics；可选查看单 key limit |

其余 30 个 provider 已接到 CodexBar collector。主 Sidebar 不放搜索，只显示当前开启的 provider；Dashboard 显示同一可见集合的卡片。直接选择 provider 只打开数据展示，不出现任何设置控件。所有 provider 管理、连接与采集配置集中在 Sidebar 的唯一 `Settings` 入口：点进去后，第二层可搜索菜单始终保留完整 34 项，每项右侧的原生开关控制它是否显示在主 Sidebar 与 Dashboard；再选择已经核对的 exact API/OAuth/Web/CLI/Local method、填写该 route 声明的临时配置，并由用户点击 `Check Usage` 执行一次采集。当前仍不能动态 Add provider，也没有重复的 Providers 页面。iOS、远程后端、长期历史、通知、自动定时刷新和跨启动凭据仍未实现。

## 后台采集引擎接线状态

Dashis App bundle 包含独立的 `DashisCollectorWorker.xpc`，用于承载 CodexBar 采集引擎。当前接线状态是：

- Sidebar 由 macOS 原生 `List(selection:)`、系统 section 与选中态组成，不含搜索；它包含 `Dashboard`、唯一 `Settings` 入口和按 catalog 顺序排列的当前开启 provider。Settings 二级菜单始终保留完整 34 项；四个 native 保留现有数据流，另外 30 个使用统一 collector 设置。
- 30 个 collector provider 共对应 41 条 live explicit route。每条 route 固定 source、exact strategy、route-manifest digest、upstream pin、允许的配置字段和风险/consent 要求；该 digest 绑定 route 执行字段，不等于完整 effect manifest。未知 route、`.auto` 与三条 automatic-only strategy 继续拒绝。
- Worker 使用 wire v4 握手，报告 63-provider Core catalog、34-provider / 52-strategy / 50-binding staging 清单，以及 41 条 live route 的 revision 和 manifest-set digest。
- 真实链路是 `App → XPC Worker → 本次操作唯一 exact strategy policy → CollectorOutcome → ProviderObservation → ProviderSnapshot`。四个 native provider 不迁移到这条 collector 链路。
- App 通过 connection-scoped、one-run reverse configuration broker，只把所选 route 声明的临时配置键释放给本次 Worker 请求；值最多解析一次，完成后即从 broker 移除。
- 启动 App 不会自动执行 CodexBar strategy，也不会因此读取 HOME、Keychain、浏览器 profile、provider CLI 或发起 provider 网络请求。
- 只有用户进入 `Settings`、选择 provider 并点击 `Check Usage` 才会执行所选 route。高风险 route 每次都要再次确认；打开展示页、进入 Settings、选择 provider/method 或上一次确认都不构成持续授权。

当前前台/staging 范围是：Codex、OpenAI、Azure OpenAI、Claude、ClinePass、Cursor、OpenCode、OpenCode Go、Alibaba、Alibaba Token Plan、Gemini、Antigravity、Copilot、z.ai、MiniMax、Kimi、Vertex AI、Moonshot / Kimi API、Ollama、OpenRouter、Perplexity、Xiaomi MiMo、Doubao、Sakana AI、Mistral、DeepSeek、Venice、Command Code、Qoder、StepFun、AWS Bedrock、Grok、LongCat、ZenMux。四个 native provider 继续走原路径；其余 30 个只有在用户显式运行时才读取对应 route 允许的来源。

其中 OpenCode Go local、Kimi CLI、MiMo local 在当前上游只能由 `.auto` planner 进入；Dashis 不允许 release collect 使用 `.auto`，所以这三条明确保持不可路由。可能使用 browser/session、Keychain、进程/子进程、写回、远程 mutation、可配置 endpoint 或潜在计费 probe 的 route 会显示风险摘要并逐次确认。确认意味着允许本次 pinned strategy 运行，不代表 Dashis 已把 Core 的全部内部访问沙箱化。

Worker 启动时会清除未在 runtime/test-safety allowlist 中的继承环境；当前 route 允许的页面值或 App 启动环境值只通过一次性 broker 临时安装，Core 直接读取 environment 或启动子进程时也只继承本 route 的值。Core 仍可能按 pinned strategy 访问 HOME 下本地 provider 文件、浏览器数据、Keychain、自己的网络客户端或 detached subprocess；login-shell locator 也可能按用户 shell 配置加载环境。因此当前是 exact route + 一次性配置 + 进程隔离 + 逐次确认，不是完整 OS、网络、凭据或存储 sandbox。

Dashis 永远不走 Mac App Store。当前开发构建仍是 ad-hoc 签名；正式分发时会采用 Developer ID、Hardened Runtime 与 notarization，并让 App、XPC Worker 和辅助 executable 使用同一签名身份。

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

下面两个脚本都会通过 LaunchServices 打开一个可见的 Dashis 窗口。自动化或 Agent 默认只使用 `docs/TESTING.md` 中的 `xcodebuild build` / `build-for-testing` 做后台验证，不运行 `build_and_run.sh` 或 `/usr/bin/open`；只有用户明确要求前台启动或视觉验收时才打开 App。

在项目根目录运行：

```sh
./script/build_and_run.sh
```

需要同时确认 App 已启动并保持运行时：

```sh
./script/build_and_run.sh --verify
```

脚本会停止旧的 Dashis 进程，构建包含 Claude helper 与 Collector XPC Worker 的 macOS Debug App，准备生成 bundle 的 xattr，再通过 LaunchServices 打开。构建使用 `ENABLE_DEBUG_DYLIB=NO`，避免临时 App 依赖 Xcode debug dylib/stub executor。Codex App 中的 Run action 调用同一脚本。启动完成只会展示目录，不会自动运行 41 条 collector route。

开发者需要只看合成数据的视觉回归时，可先按 `docs/TESTING.md` 构建，再用 `--visual-qa` 打开 Debug App。该 fixture 只注入合成 Codex snapshot 并进入 Codex detail；初始化不读取账户文件、credential 或真实响应，也不自动检查 provider。它不在 Release 生效，也不能替代真实 provider 验收。

## 界面导览

启动后应看到：

- Sidebar：窗口使用系统 `NavigationSplitView`。Sidebar 列表最上方保留原有 28 pt semibold Serif `Dashis` 品牌和原位置，主列固定为 218 pt；其后是 `Dashboard`、唯一 `Settings` 入口和当前开启的 provider，没有搜索框。所有标签都在列内压缩并尾部截断，不会因为 Settings 的二级菜单而从窗口左边被裁掉。provider 列表可滚动，没有重复的 Providers 页面或 Add provider；普通导航行的行高、选中态与强调色由 macOS 接管。
- Provider navigation：每项只显示 provider 名称，不再用 `network`、`cloud`、`terminal`、`globe` 等泛化图标，也没有装饰性 chevron、连接 badge 或指标数量。选择一行只打开纯数据展示页，不会自动运行采集，也不会出现设置表单。
- Dashboard：按同一 catalog 顺序显示当前开启 provider 的统一系统卡片；内容宽时双列、空间不足时单列。collector 未检查时明确显示 `Not checked`；整张卡可以打开相应展示页，但没有 Check、Connect 或 `Configure` 按钮，也不会自动采集。若全部关闭，Dashboard 会显示 `No Providers Shown` 系统空态并提示到 Settings 恢复。
- Provider display：使用最大 900 pt 的纯展示 `ScrollView`，页面只有一张系统 `GroupBox` 主卡；尚未采集时只显示 provider 名称和真实空态。展示区不出现 method、credential、bridge/OAuth、risk/consent、Check、Clear、Advanced 或 Recent calls 控件。
- Settings：点击顶层 `Settings` 后，唯一外层导航的 detail 区域会固定显示一个 220 pt、不可折叠的 provider 面板。顶部是 macOS 原生搜索字段，下面的系统 `.inset` List 按固定顺序始终包含全部 34 项；每行右侧是系统原生 switch：开启表示显示在主 Sidebar 与 Dashboard，关闭表示只从这两个展示入口隐藏。长名称会单行尾部截断并可悬停查看全名。选择 provider 后，右侧才出现最大 900 pt 的系统 grouped `Form`，字段最多 420 pt。这里没有第二个 split、可拖动分隔线或二级 Sidebar 恢复按钮。collector 只显示 Connection、按需 Credentials、主操作和 Advanced；method、内存生命周期、Access 重复项和风险摘要不常驻显示。高风险 route 点击主操作后才显示一次确认框。四个 native provider 的解释 footer 同样移除，只保留字段、真实状态和操作。清除操作只在确有本地状态时出现在 section header 的 ellipsis 菜单。
- Usage hierarchy：Dashboard 卡与 provider 详情卡复用同一数据优先级。有 snapshot 时，订阅/限额型结果优先显示实际返回的前两个窗口；若 provider 真实提供 5-hour/7-day，它们是最大的两个数值，但 Dashis 不会凭计划或字段名补造窗口。余额/充值型结果没有主窗口时，真实 balance 位于第一视觉层级；可验证进度使用系统 `ProgressView`。两个主值只是同一外层卡内的 pane，不再分别套小卡。Dashboard 卡只保留这些主数据，额外 usage/metadata 进入 provider 详情卡内的折叠区。
- Secondary detail：额外 quota/metric 与 source/scope/observed metadata 在同一主卡内默认折叠；warning 与 partial failure 在卡内各完整显示一次，但不套额外 surface。界面不再把 snapshot 展开成一长张 raw key/value 表。

当前外壳以 macOS 26/27 系统组件为准：全窗口只有一个默认样式的外层 `NavigationSplitView`，主 Sidebar 固定 218 pt；Settings 的 220 pt 面板只是 detail 内的固定原生控件组合，不拥有导航列状态。系统搜索、List、switch、Divider、title、Dashboard `ScrollView` / `LazyVGrid` / `GroupBox`、展示 `ScrollView`、grouped Form、Section、LabeledContent、ProgressView、toolbar/menu 和按钮会随平台外观变化。原有 Serif `Dashis` 品牌、位置与主 Sidebar 宽度是刻意保留的产品身份；该风格不扩散到 provider 导航或正文。Dashis 不手绘 Liquid Glass、不固定黑白页面、不自定义导航选中背景、开关或卡片阴影；只在 warning、failure 与更多操作等真正有语义的位置保留系统符号。

## 控制首页显示的 provider

1. 在主 Sidebar 选择 `Settings`。
2. 在第二层菜单中搜索或滚动到目标 provider。即使它已经从首页隐藏，也始终能在这里找到。
3. 使用该行最右侧的系统 switch：关闭后，provider 会同时从主 Sidebar 和 Dashboard 消失；重新开启后，它会按固定 catalog 顺序回到这两个位置。

这个开关只管理展示范围，不是断开连接或清除数据：它不会删除 provider、临时配置、已加载 snapshot、collector route 或采集能力，也不会自动运行 Worker。开关状态只以 provider ID 作为非敏感偏好跨启动保存；API key、token、Cookie 和 provider 响应不会因此写入 UserDefaults。若上次退出时正停留在 Settings 或后来被隐藏的 provider，下一次启动会安全回到 Dashboard；需要配置时再从主 Sidebar 点击 Settings。

## 30 个 collector provider 的统一操作

每个 collector provider 都按同一顺序操作：

1. 在主 Sidebar 选择 `Settings`。
2. 在第二层 provider 菜单中搜索或滚动，选择目标 provider；这一步只切换设置表单，不会执行采集。
3. 在 `Method` 中选择一个可读的采集方式；不存在 `.auto` 选项。
4. 根据当前 route 填写显示出来的临时配置字段；敏感项使用 SecureField。没有字段时不会额外显示 Access 或 session 说明。
5. 若需要排障或核对实现，展开 `Advanced` 查看 exact source、route 和 adapter；常规使用不需要展开。
6. 点击唯一的主操作 `Check Usage`。
7. 若 route 属于高风险，此时才会显示本次确认框；阅读后选择 `Run Check`，取消则不会执行。
8. 检查结束后，从主 Sidebar 或 Dashboard 打开该 provider 的纯数据展示页；真实 quota/balance/metric 会进入单张主卡，额外数据仍在卡内折叠。需要清除时回到 Settings 中该 provider 的 Connection section，打开 ellipsis 菜单并选择 `Clear Session Data`。

临时配置值只存在于当前 App 内存，并只通过本次 connection/route/lease 绑定的 reverse broker 释放一次；不会写入文件、UserDefaults 或 Keychain。切换 method 时只会提交新 route 声明的键。`Clear Session Data` 会清除该 provider 的输入、observation 和 snapshot，并使在途旧结果失效。

字段可以留空；页面没有输入时，App 仍会把启动环境中与当前 route 同名的键经同一个一次性 broker 释放。若两者都没有，匹配的 Core strategy 仍可能使用本地 provider/CLI/browser 配置。Worker 不会直接继承其它 provider 环境变量；但空字段仍不是“无本地访问”的证明。

自动测试和普通界面验收不点击 `Check Usage`、不输入真实 credential，也不运行真实 provider。只有用户要验收自己的账户时，才在理解 route 风险后显式执行；不要把真实值放进截图、日志、issue、fixture 或文档。

## Codex

### Personal desktop usage

1. 确认当前 macOS 用户已经在 Codex Desktop/CLI 使用同一套本地登录材料。
2. 在主 Sidebar 选择 `Settings`，再从第二层菜单选择 `Codex`。
3. 点击 `Check Desktop Usage`。
4. 检查完成后，从主 Sidebar 或 Dashboard 打开 `Codex` 展示页查看主卡。

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

在 `Settings → Codex` 的 `Workspace analytics` section 输入：

- `workspace id`。
- 具有 `codex.enterprise.analytics.read` scope 的 analytics API key。
- 1–90 天的 Analytics window。

点击 `Check workspace analytics`。Dashis 会分页读取官方 workspace usage，每页最多 500 条、最多 100 页。它展示的是组织 workspace 聚合 activity/turn/token，不是个人订阅 remaining。

Analytics key 只在当前 App 内存中存在。点击 `Clear Codex data` 会清空 Codex 输入与已加载 snapshot；退出 App 后也不会保留。不要把真实 key 写入文档、截图、issue、测试或日志。

## Claude

### 连接本地 bridge

Claude quota 来自 Claude Code 官方 `statusLine.rate_limits`。Dashis 不读取 Claude auth、Cookie、transcript，也不会为了刷新额度自动发送 Claude 请求。

1. 在主 Sidebar 选择 `Settings`，再从第二层菜单选择 `Claude`。
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
2. 回到 `Settings → Claude` 点击 `Reload Usage`。
3. 从主 Sidebar 或 Dashboard 打开 `Claude` 展示页查看 5-hour/7-day 主卡。

若 Claude Code/订阅提供 `rate_limits`，Dashis 会显示 5-hour 和/或 7-day window，并计算 remaining = 100 - used。一个窗口可能单独缺失；没有 `rate_limits` 的 statusLine 事件不会清除旧值，也不会把旧数据重新标成刚更新。

本地 snapshot 超过 15 分钟显示 stale，超过 24 小时显示 expired。产生新的 Claude Code 响应后再 Reload；Dashis 不会替你发送请求。

### 清除与断开

- `Clear loaded data`：只删除经过安全校验的净化 snapshot，不修改 Claude statusLine；bridge 仍保持连接。
- `Preview disconnect`：只生成恢复预览。
- `Preview disconnect` 后 `Apply change`：恢复连接前的 statusLine（没有旧 command 时移除 Dashis statusLine），并删除安全 snapshot。

如果 settings 在 Preview 与 Apply 之间变化，Apply 会拒绝覆盖；重新 Preview 后再决定。

## Google AI

`Settings → Gemini` 顶部有两个互斥 mode。切换 mode 会取消当前 Google OAuth 操作并清除当前展示的 Google snapshot；必要时需要重新连接/检查。采集或人工记录完成后，从主 Sidebar 或 Dashboard 打开 Gemini 展示页查看数据。

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
7. Dashis 连接成功后会自动检查一次；之后可点击 `Check Quotas` 重查。
8. 从主 Sidebar 或 Dashboard 打开 Gemini 展示页查看 quota 主卡。

quota ID 可从目标项目的 Cloud Quotas 控制台或官方 `quotaInfos.list` 响应中的 `quotaId` 字段取得，不要填 display name。留空时 Dashis 会按受支持 cadence 优先、稳定排序，最多自动选择 24 个 definition；输入 exact ID 可进一步缩小 Monitoring 请求范围。

授权只请求 `https://www.googleapis.com/auth/cloud-platform` scope，使用随机 `127.0.0.1` loopback port/path、PKCE S256 与 state。access token 只在当前 App session 保留；refresh token 和 ID token 被丢弃。浏览器本来已登录只会减少登录步骤，不代表 Dashis 已自动获得授权。

Dashis 从 Cloud Quotas 读取有效 limit，再从 Cloud Monitoring 读取对应 limit/usage series。只有 quota ID、`limit_name`、dimension/model/location、metric type 和窗口可可靠匹配时才计算 remaining；否则显示 unavailable/警告。region/zone 会与 Monitoring 的 exact location label 对齐。minute/hour 会选择最新完整且已可见的历史窗口；摘要把主值明确标为 `historical`，detail 只在对应 window/warning 中给出一次 exact `as of`。它不是当前实时分钟余额。RPD 按 `America/Los_Angeles` 日历午夜重置。

Cloud Monitoring 通常可能延迟约 150 秒，因此刚产生的请求不一定立即出现。Project 结果标为 `Official · Estimated`，不是 provider 直接返回的余额。

Consumer mode 的 `Clear Google data` 或 Project mode 的 `Clear Google session` 会取消 Google 的本地 OAuth listener 和在飞请求，清除 access token、client/project/quota-ID/manual 输入与 snapshot；不会撤销 Google 账户中的其它授权或修改项目 IAM。

## OpenRouter

`Settings → OpenRouter` 有 `Account` 与 `Single key` 两个 mode，默认是整个账户视角。切换 mode 会取消当前 OpenRouter OAuth 操作、清除该 provider 的临时 credential 和 snapshot；必要时重新输入 management key 或重新连接 single key。用量结果在主 Sidebar/Dashboard 对应的 OpenRouter 纯数据展示页查看。

### 默认 Account

1. 保持 `Account` mode。
2. 在主 Sidebar 选择 `Settings`，从第二层菜单选择 OpenRouter；再点击 `Open OpenRouter`，在官方页面创建 Management API key。
3. 回到 Dashis，把 key 临时输入 `Management key`；它只在当前 App session 保留。
4. 点击 `Check Whole Account`。
5. 若要看近期调用，先等账户检查成功，再进入 `Recent calls` section。
6. 选择 1–30 天窗口并点击 `Load call metadata`。
7. 从主 Sidebar 或 Dashboard 打开 OpenRouter 展示页查看账户 credits 主卡。

Account 主卡显示 OpenRouter 账户累计购入 credits、累计消费和 `total_credits - total_usage` 得出的 remaining。它不是某一把普通 API key 的消费上限，也不要求其它程序或后续模型调用改用 Dashis 的 key。

同一次检查还会读取：

- `/activity`：账户最近 30 个已完成 UTC 日的聚合活动，不加 `api_key_hash` 或 `user_id` 过滤。它按日期、endpoint/model/provider 聚合，不是逐调用原始日志。
- `/analytics/meta` + `/analytics/query`：在 `Account analysis` 指定的 1–90 天窗口内读取账户分析；请求显式带 time range，默认不加单-key filters。
- 可选 `/generation?id=...`：只有你已有 generation ID 时才读取那一次调用的 metadata。Dashis 不读取 prompt/completion 内容。

近期调用区会通过 analytics 的 `generation_id` dimension 读取最多 20 条账户级 metadata 行，并在可用时附带 key/model 标签、时间 bucket、usage/cost 和 token。请求显式使用 `group_limit: 1` 与总 `limit: 20`，避免 OpenRouter 对 time-series 查询自动提高返回行数。它是独立查询：失败不会清掉已经成功显示的账户余额。

OpenRouter 官方目前没有一个带 cursor、可直接列出全部逐调用 generations/logs 的公开 API，因此这个列表不是完整历史，也不保证恰好是“最新 20 条”。同一 ID 会去重，OpenRouter 也可能返回 `truncated`；Dashis 会明确提示，而不会把结果称为全部日志。修改 Call window 会清掉旧列表，需重新点击加载，防止把旧 1 天结果误看成新 30 天结果。Dashis 不请求 prompt/response，也不调用 `/generation/content`。

Management key 本身可以管理账户 key，权限高于普通推理 key，而且不能用于模型 completion。Dashis 只把它保存在当前 App 内存中，并且 endpoint allowlist 不允许 `/api/v1/keys` 的创建、修改、禁用或删除操作。`Clear local session` 会清掉内存中的 management key、输入、snapshot 与 recent-call metadata。

### 可选 Single key

只有想检查某一把普通 key 自己的 limit/usage/remaining 时才切换 `Single key`：

1. 点击 `Connect OpenRouter`。
2. 在系统默认浏览器中确认授权；OpenRouter 会创建/返回一把用户控制的普通 API key，并可能要求设置该 key 的消费上限。
3. 回到 Dashis 完成 `/api/v1/key` 检查，再从主 Sidebar 或 Dashboard 打开 OpenRouter 展示页查看 key-level limit、usage、`limit_remaining`、reset/expiry。

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
- collector 临时配置、Codex Enterprise key、OpenRouter key、Google access token、OAuth state/PKCE verifier 都不会写入 UserDefaults、仓库、文档、日志或 Keychain。
- Clear 会使当前 provider 正在执行的旧响应失效，防止它稍后重新填回已清空的 UI。
- Claude 净化 snapshot 是唯一受控的本地用量文件；它不包含凭据，并可由 Clear/Disconnect 删除。
- 遇到错误时只分享净化后的错误类别。不要复制真实 Authorization、账号 ID、完整 request/response 或 provider 页面中的私人数据。
- collector 的 one-run broker 会限制 route 配置环境变量，但不是完整 sandbox；Core 仍可能读取 HOME 下本地 provider/CLI/browser 配置、Keychain、网络或启动 detached subprocess。

## 手动验收清单

- `./script/build_and_run.sh --verify` 构建并启动成功。
- 构建产物包含 `Dashis.app/Contents/XPCServices/DashisCollectorWorker.xpc`；后台 wiring test 能完成 wire v4 握手、核对 34/52/50 staging 清单、41 条 live route、live revision/manifest-set digest，并读取 63-provider catalog；未知 route 默认拒绝。
- Sidebar 使用系统 `List(selection:)`；列表顶部完整显示不可选择的原有 28 pt Serif `Dashis` 品牌名，位置与原版一致，主列固定为 218 pt；其后完整显示 `Dashboard`、唯一 `Settings` 入口与当前开启 provider，不得统一裁掉 leading 字符，也没有重复的 Providers 页面或 Add provider。
- 主 Sidebar 没有搜索框，并按 selected catalog 顺序显示当前开启 provider；Gemini 继续复用内部 `google` 导航/原生数据流。选择 provider 只进入纯数据展示页。
- Dashboard 没有 WebView、网页、Node gateway、旧 mock telemetry 或 runs。
- Dashboard 按 catalog 顺序显示当前开启 provider 的系统卡片；宽窗口双列、窄窗口单列。collector 未检查时显示 `Not checked`。Dashboard 整卡没有 Check、Connect 或 `Configure` 按钮，只打开纯数据展示页且不自动采集；全部关闭时出现指向 Settings 的系统空态。
- 每个 provider 展示页只有一张系统 `GroupBox` 主卡；无 snapshot 时只显示 provider 名称和诚实空态，有 snapshot 时主要 quota/balance 或 KPI 在同一卡片内最多两个 pane 中显示。展示页完全没有配置 Form 或动作。
- 点击顶层 `Settings` 后出现第二层可搜索 provider 菜单，始终完整显示同一 34 项；每项右侧是系统原生 switch。关闭任一项后，它只从主 Sidebar 与 Dashboard 同时消失，Settings 中仍可选择并重新开启，已有 snapshot/配置/route 不变，重启后开关状态保持。选择 provider 后，真实设置 Form 只显示 Method、必要字段、唯一主操作和折叠的 `Advanced`；method/credential/lifecycle/risk 说明不常驻，风险只在执行时确认。四个 native provider 的连接、凭据、bridge/OAuth、检查和 recent-call 控件也只在这里，且没有解释 footer。
- 分别在默认 1160 × 760 和最小 960 × 640 下进入 Settings、搜索、选择 `Alibaba Token Plan` 或 `Moonshot / Kimi API` 等长名称、切换右侧 switch 时，218 pt 主 Sidebar 与 220 pt 固定设置面板都应完整存在；`Dashis`、Dashboard、Settings 和 provider 名称的左边必须完整可见，右上角不得出现二级 Sidebar 的双箭头恢复按钮。二级边界不可拖动；长名称允许尾部截断，不能为了显示全名加入左右 padding 或撑宽 Spacer。关闭窗口前停在 Settings 时，重新启动应先回到 Dashboard。
- 一个页面同一状态只有一个高优先级主操作；Clear 在有本地状态时才进入 ellipsis 菜单，并保留原有确认、generation invalidation 和必要的服务端 revoke 提示。
- 订阅/限额型结果的前两个实际窗口位于 Dashboard 卡和详情主卡的第一视觉层级；真实 5-hour/7-day 优先，但缺失时不伪造。余额/充值型结果在没有主窗口时优先显示真实 balance；两个主值不各自套小卡，Dashboard 卡也不重复展示额外 metadata。
- 只有已知 percentage 或可验证 numerator/positive denominator 的主卡条目显示进度；limit-only、未知 denominator 与普通 KPI 不显示伪造 `0%`。
- warning 与 partial failure 在同一主卡内各完整显示一次且不另套 surface；展开 More usage data / Data details 后不重复主值。
- no-data 摘要只用主值表达空态；真实来源风险与异常限定词和实际路径一致。
- Codex personal 为 Experimental；没有实际窗口时不显示推断的 5-hour/weekly 限制，credits 与 available reset credits 分开；Enterprise 是 workspace usage，不冒充个人 remaining。
- Claude Preview 无持久写入，Apply 才安装 helper并改 settings；已有 statusLine 连接/断开后能恢复。
- Google consumer 只人工查看；Project mode 显示 Estimated 和约 150 秒延迟警告。
- OpenRouter 默认 Account mode 显示账户 remaining 和无单-key过滤的聚合活动；账户成功后可加载 1–30 天、最多 20 条 metadata-only recent calls，截断提示清楚且失败不影响余额。Single key 的 OAuth 取消、拒绝、超时、key 过期都有净化错误，Clear 后必要时能按指引去服务端 revoke。
- 所有 SecureField/session token 在 Clear 或 App 退出后不可复用；日志和 UI 不泄漏凭据/完整响应。
- collector 临时配置只在内存中；method 切换不会提交旧 route 的键，`Clear Session Data` 会清除输入、observation 与 snapshot。高风险 route 每次检查都重新确认。
- 在 macOS 26/27 的 light/dark 下验收唯一外层 `NavigationSplitView`、Sidebar/title/List、Settings 固定 220 pt 原生搜索/List/switch 面板、Dashboard ScrollView/LazyVGrid/GroupBox、展示 ScrollView、grouped Form/Section/LabeledContent/ProgressView/menu/按钮外观；Sidebar 顶部必须完整保留原有 Serif `Dashis` 与位置，主列固定 218 pt，但不添加品牌图标/副标题，也不把 serif/offset 扩散到 provider 导航。Dashboard 应显示统一自适应 provider 卡，provider 详情页应只有一张系统主卡；两处都无嵌套小卡、自绘材质、描边或阴影。Settings 配置页不得有第二个 split、二级折叠按钮或可拖动边界，并应保持原生开关、section 分组、统一字段宽度和一个靠右主操作；默认/最小窗口都不能再出现整列 leading 裁切。
- Debug `--visual-qa` 只显示合成 Codex snapshot，不读取账户/credential、不自动联网，Release 不启用。
- 启动 App、浏览 Sidebar、打开 provider 展示页、进入/搜索 Settings、切换二级 provider 或显示开关不会自动唤起 Worker、执行 CodexBar strategy、读取凭据或联网；只有在 Settings 中显式点击 `Check Usage` 才运行一次。
- 普通手动 UI/文档验收不点击 `Check Usage`，不输入真实 credential，不运行真实 provider；使用合成测试验证 route、broker、consent 和 Observation→Snapshot 链路。

## 常见问题

### `./script/build_and_run.sh --verify` 失败

查看最近系统日志：

```sh
/usr/bin/log show --style compact --last 2m --predicate 'eventMessage CONTAINS[c] "Dashis" OR eventMessage CONTAINS[c] "com.Vita0818.DashisMac" OR eventMessage CONTAINS[c] "AppleSystemPolicy" OR eventMessage CONTAINS[c] "AMFI"'
```

如果出现 AppleSystemPolicy/AMFI 拒绝，确认脚本仍使用 `ENABLE_DEBUG_DYLIB=NO`，并执行生成 bundle 的 provenance/quarantine xattr 准备。

### Xcode Console 出现 logging timeout

shared scheme 已设置 `IDEPreferLogStreaming=YES`。`Failed to initialize logging system due to time out` 不一定代表 App 崩溃；同时检查 Dashis 进程和系统 crash/AMFI 日志。

### Collector Worker 缺失或握手失败

开发构建中，Worker 应位于：

```text
Dashis.app/Contents/XPCServices/DashisCollectorWorker.xpc
```

先按 `docs/TESTING.md` 重新执行 Xcode build/test，检查 XPC bundle ID、embed phase、wire version 4、41 条 live route、live revision/manifest-set digest 和 App/Worker 签名是否一致。不要通过运行真实 provider、读取真实凭据、改成 `.auto` 或放宽 exact authorization 来验证接线；正常 wiring test 使用 handshake、catalog 与合成 route。

### Collector `Check Usage` 被拒绝

- `unknown_route` 或 manifest/pin/revision mismatch：App 与 Worker 很可能不是同一次构建；重新构建，不要手工放宽 route。
- configuration broker/lease 错误：重新进入并发起一次新 check；只填写当前 method 页面显示的字段，不要尝试传任意环境变量。
- `route_consent_required`：返回详情，在本次确认框中阅读风险后决定是否运行。Dashis 不会复用上次 consent。
- strategy unavailable 或配置缺失：确认选择的 method 与本机已有 provider/CLI 配置匹配，或只在当前页面临时填写 route 声明字段。不要把真实配置贴进日志或 issue。
- timeout/cancel：界面会拒绝迟到结果；Worker 会 cancel、关闭 Core 持久会话、等待 2 秒，并在必要时终止自身 process group 后退出。自行脱离该 process group 的子进程仍需发布级验证。

即使页面字段留空，Core 也可能读取本地 provider 文件、CLI/browser 配置或 Keychain；App 启动环境中的同名 route key 也会通过一次性 broker 租给本次操作。排障时不要打印 App/Worker environment，也不要把当前实现称为完整 sandbox。

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
