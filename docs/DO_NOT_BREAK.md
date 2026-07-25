# DO_NOT_BREAK

本文列出 Dashis 当前不可破坏的工程、数据、provider 和用户流程边界。源码、工程配置与测试是当前事实；不能把未确认能力写成已实现。

## 仓库与工程禁区

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、验证或准备工作不等于提交请求。
- 若用户要求提交，只处理当前 Git root 中与任务相关的文件；不递归修改、暂存、提交或推送 submodule、nested Git repo 或依赖 checkout。
- 不安装依赖、初始化新构建工具或修改 Vitemis 其它项目，除非用户明确要求。
- 不删除或降级 `Dashis`、`ClaudeStatusLineHelper`、`DashisTests` target、shared `Dashis` scheme、App 对 helper 的依赖或 `Embed Claude Helper` build phase。
- 不把 build 生成物写进仓库；DerivedData 继续使用系统临时目录或显式的临时路径。
- iOS target 与共享代码边界尚未确认；不得提前把 `App/macOS` 移成跨平台共享层或声称已有 iOS 支持。

## 产品与 UI 禁区

- 不把 Dashis 退回网页形式：不重新引入 `WKWebView`、Web dashboard 主入口、Node localhost gateway、React/Vite/Next 或静态 HTML/CSS/JS dashboard。
- Dashboard 必须保持 provider-first：Sidebar 固定为 Dashboard、Codex、Claude、Google AI、OpenRouter；首页固定为四条内置 provider 摘要。没有实际偏好设置前，不恢复说明型 Settings 页面。摘要必须保持带分隔线的扁平列表，不能重新膨胀为嵌套卡片墙。
- 不恢复动态 Add provider、自定义 session provider、旧 Models/Runs/Alerts、首页小指标网格、右侧 inspector-first、Recent monitors、timeline、装饰性品牌块或 marketing landing page。
- 不把主题改成 Intatis 的香槟金、暖米色、紫蓝渐变、深蓝 slate 或其它非系统白/黑主色；语义色只表达状态。
- 不得替换 Dashis 原有字体身份：品牌、页标题与主数值保持 macOS system serif，正文、控件与辅助信息保持 system sans；不得把普通正文改成 serif 或 monospace，代码/日志类内容才可局部使用 monospace。
- 不得以“参考 Codex 网页”为由重写 Dashis 外壳。旧版外壳的硬约束是：品牌 28 pt serif、页标题 32 pt serif、Sidebar min 176 / ideal 218、导航约 14 pt serif 与约 40 pt 行距、浅蓝选中态、详情 horizontal 30 / top 26 / bottom 30 外边距及 14 pt 纵向 spacing；provider 内容最大宽度 900，外层最大宽度 1180。Codex 参考只允许影响信息层级与去重方式。
- 空态摘要只保留 provider 名称、主值和一个动作；不得恢复 kind、正常 source/freshness、辅助统计、caption、进度或解释小字。真实来源风险、historical/stale/expired、warning、failure 与 exceeded 仍必须可辨认。
- provider detail 无 snapshot 时不得显示占位明细或默认帮助段落；有 snapshot 时必须经类型化 projection 展示完整归一化窗口、warning 或 partial failure，而且同一份数据只展示一次，不能退回原始扁平 key/value 表。
- provider detail 只为主要 quota/balance 或主 KPI 使用两列卡片；当前 App 最小布局下不得无故退化为单列，只有未来布局约束确实不足时才允许一列。额外 quota/metric 与 metadata 必须默认折叠；warning/failure 不套额外卡片，并各完整展示一次。
- 不为 source/scope/observed、warning、failure 或每条普通 metadata 单独套卡片/边框，也不在 provider detail 同时复制完整 Dashboard 摘要。卡片内部不得重复同一数值的 used/limit/remaining 文案；只保留主值、descriptor、必要 reset/status 与可验证进度。

## 统一数据语义禁区

- 不绕过 `ProviderSnapshot` / `QuotaWindow`，也不让 adapter 直接拼接最终 UI 状态来替代结构化数据。
- 不删除或模糊 source 语义：`Official`、`Official · Estimated`、`Official · Local`、`Experimental`、`Manual check` 必须保留在 snapshot 与无障碍语义中。中性空态可隐藏视觉 source；真实实验、推导、手动或风险数据需要判断时，必须用准确且最短的限定词呈现。
- 没有可信数据时只用主值显示 `No data` 类空态，不再追加重复 source/freshness 提示；不得用计划上限、默认值、旧 mock、历史值或空响应伪造当前 remaining。
- 不把 no-data snapshot 标成 fresh。Freshness 必须基于真实数据与真实 `observedAt`；未来时间、过期文件和没有新 Claude 窗口的事件不能续命旧数据。
- 不钳制原始 negative remaining，也不丢弃 used > limit / used percentage > 100 的超额事实；只有 percentage 已知或 numerator/positive denominator 均可验证时才能显示进度。未知 denominator、limit-only 或普通 KPI 不得显示伪造的 `0%`；只允许最终进度条视觉 fraction 限制在 `0...1`。
- 不把推导值显示成官方直接余额。Google Cloud quota 必须保持 `Official · Estimated`，Google consumer manual 必须保持 `Manual check`。

## 网络与 endpoint 禁区

- 所有 provider 远端请求必须经过 `ProviderHTTPClient` 与 `ProviderEndpointPolicy`；不得回退到 `URLSession.shared` 或为方便而放宽全局 host/path/query/body 验证。
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

## 凭据与隐私禁区

- 不读取、打印、摘要、复制、发送或写入 `.env`、API key、token、password、Cookie、session、私钥、证书、SSH key、Keychain 内容、浏览器 profile 或无关私人文件。
- 不把真实 API 响应、用户数据、账号标识、完整日志、请求体、prompt、completion、成本账单或个人隐私路径写入 docs、report、fixture、截图或 Git。
- OpenRouter OAuth key/management key、Google access token、Codex Enterprise analytics key 和 OAuth/PKCE 中间值只存在于当前 App session；不得写入 UserDefaults、文件、日志、Keychain 或 analytics。
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
