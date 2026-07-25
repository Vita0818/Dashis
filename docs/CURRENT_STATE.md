# CURRENT_STATE

## 当前状态

- 项目名：Dashis；独立 Git root 为 `/Users/vita/Vitemis/Dashis`，远程 `origin` 为 `https://github.com/Vita0818/Dashis.git`。
- 当前产品是 macOS 原生 SwiftUI provider-first dashboard；没有 WebView、网页入口、Node gateway 或旧 mock telemetry/runs。
- `Dashis.xcodeproj` 当前包含三个 target：macOS App `Dashis`、命令行 helper `ClaudeStatusLineHelper`、单元测试 `DashisTests`。shared scheme `Dashis` 会构建 App/helper 并运行测试 target。
- `script/build_and_run.sh` 是本地 build/run 入口；`.codex/environments/environment.toml` 的 Run action 调用该脚本。
- 当前只实现 macOS；iOS target 仍为 `UNKNOWN`。

## 已实现能力

### 统一 provider 模型

- Dashboard 在一个紧凑列表中固定展示 Codex、Claude、Google AI、OpenRouter 四条内置 provider 摘要，侧边栏只提供 Dashboard 与这四个详情入口；没有实际可配置内容的说明型 Settings 页面已移除。
- 所有 adapter 返回 `ProviderSnapshot` / `QuotaWindow`；空态 Dashboard 摘要只显示 provider 名称、主值和一个主动作，不显示 kind、source、freshness、辅助统计或解释小字。Dashboard 仍是带分隔线的四 provider 扁平列表，没有把摘要重新膨胀成卡片墙。只有真实数据来源或 historical/stale/expired/partial/failed/exceeded/warning 等风险需要辨认时，才增加一个最短限定词。
- provider detail 无 snapshot 时直接显示主操作控件，不渲染占位明细、帮助段落或无状态可清的 Clear 动作；有本地状态后才显示对应 Clear。有 snapshot 时，返回的 quota/balance 或主指标通过类型化 projection 放入两列主卡片；额外指标与 source/scope/observed metadata 默认折叠。warning 与 partial failure 不套额外卡片，在主内容下各完整展示一次。
- 数据来源分为 `officialDirect`、`officialDerived`、`officialLocalBridge`、`experimentalPrivate`、`manualOnly`；UI 不把推导值、私有 endpoint 或手动值伪装成官方实时余额。
- 原始 remaining 允许为负数；只有服务端返回 percentage，或存在可验证 numerator/denominator 时才显示进度，且仅视觉 fraction 投影到 `0...1`。未知 denominator、limit-only 或 KPI metric 不伪造 `0%` 进度。Dashboard 不重复渲染 caption、进度、统计小卡或明细行，完整窗口/警告留在 provider detail。

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

### Google AI

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

### 安全网络与验证

- `ProviderHTTPClient` 使用 ephemeral `URLSessionConfiguration`，禁用 cache、cookie 与 credential store；所有 redirect 均拒绝，429/502/503/504 与有限瞬时网络错误最多重试一次。
- `ProviderEndpointPolicy` 同时校验 HTTPS、精确 host/path、method、query、body schema 与端口；OAuth 授权 URL 和 localhost callback 另有严格校验。
- `Clear` 会失效当前 provider generation、关闭活动 OAuth listener，并清除临时 key/token、输入、PKCE/OAuth 会话引用与内存 snapshot，避免迟到响应重新写回。
- `DashisTests` 当前定义 84 个纯合成、离线测试，覆盖 decoder、Codex credit-only/windowless/dynamic-window 语义、类型化卡片 projection、未知 denominator 不显示进度、OpenRouter 账户默认入口/无单-key过滤、recent-call metadata sidecar、迟到响应隔离、balance/window 去重、数值溢出与负 remaining、reasoning、analytics metadata、allowlist、PKCE、Claude 净化/settings 恢复、Google quota 推导与 freshness；不访问真实账户。

### UI 与视觉验收

- 主界面保留 Dashis 原有字体层级：品牌、页标题与主数值使用 macOS system serif，正文、descriptor、控件与辅助信息使用 system sans；只有代码/日志类内容使用 monospace。
- 当前视觉改动是恢复旧版 Dashis 外壳，不是重新设计一套壳层：品牌固定为 28 pt serif，页标题固定为 32 pt serif；Sidebar 列宽保持 min 176 / ideal 218，导航保持旧版约 14 pt serif、约 40 pt 行距与浅蓝选中态。详情区保持 14 pt 纵向间距、horizontal 30 / top 26 / bottom 30 外边距，provider 内容最大宽度 900，外层内容最大宽度 1180。
- Codex 网页只作为 quota/balance 信息层级和去重方式的参考，不能据此替换 Dashis 的字体、Sidebar、字号、位置、间距或品牌身份。
- provider detail 的主 quota/balance/metric 卡片使用低对比边框、轻阴影和明确留白；当前 App 最小布局支持两列。只有未来窗口约束确实不足时才允许降为一列，不能在当前支持范围内无故堆成长列表。
- `--visual-qa` 只在 Debug 构建中注入合成 Codex snapshot 并打开 Codex detail，用于截图和视觉回归；fixture 初始化不读取账户文件、provider credential 或真实响应，也不会自动发起网络检查。Release 构建不启用该 fixture。

## 当前验证状态

- `plutil -lint Dashis.xcodeproj/project.pbxproj`：通过。
- `xcodebuild -list -project Dashis.xcodeproj`：可发现 `Dashis`、`ClaudeStatusLineHelper`、`DashisTests`。
- macOS Debug build：通过，helper 被嵌入 `Dashis.app/Contents/MacOS/dashis-claude-statusline`。
- `xcodebuild test`：84/84 通过；所有测试均为离线合成 fixture，不读取真实 provider 数据。
- `script/build_and_run.sh --verify`：通过；脚本完成 Debug build、LaunchServices 注册并确认 Dashis 进程保持运行。
- 真实 provider 账户仍需用户在 UI 中主动授权后人工验收；自动测试不会读取任何真实凭据。

## 未确认

- iOS target、共享代码边界与移动端 OAuth/bridge 方案。
- dashboard 的长期用户角色、业务 KPI、刷新调度、通知、数据保留和后端需求。
- 是否允许未来将 OpenRouter/Google refresh token 持久化到 Keychain；当前明确不持久化。
- Codex personal `wham` 是非公开契约，可能随时变化；账户是否返回固定窗口、credits 或 unlimited 状态取决于当前计划与服务端响应，失败时必须继续 fail closed。
- Google consumer subscription 若未来发布正式余额 API，需要重新评估，不能沿用网页或 TUI 抓取。

## 工作区注意

- 工作树改动以每轮开始时的 `git status --short -- .` 为准；不得清理、回退或覆盖用户已有改动。
- 未经明确请求，不 add、commit、push 或创建 PR。
- 真实账号数据仅能通过用户显式操作进入当前 app session；不得把凭据、完整响应或私人路径写入仓库。
