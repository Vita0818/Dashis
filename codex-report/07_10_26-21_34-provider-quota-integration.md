# Dashis 多 Provider 用量与余额获取研究及推荐实施方案

> 研究日期：2026-07-10（Asia/Singapore）
>
> 报告性质：现状审计与实施建议；本报告不代表 Claude、Google AI 或新增 OpenRouter/Codex 能力已经实现。

## MODEL_CHECK_RESULT

- 当前模型：GPT-5 系列 Codex。
- 当前运行环境未提供更细的模型版本字符串，因此精确版本无法确认。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Dashis`
- Git root：`/Users/vita/Vitemis/Dashis`
- 结果：两者一致，匹配预期仓库。
- 工作区状态：存在较多用户已有未提交改动；本报告不覆盖、回退或整理这些改动。

## FILES_WRITTEN

- 新增：`codex-report/07_10_26-21_34-provider-quota-integration.md`
- 未修改业务源码、Xcode 工程、测试源码或 `docs/` 下的现有项目文档。

## SUMMARY

### 1. 结论摘要

Dashis 可以继续保持当前 macOS 原生 SwiftUI、provider-first 架构，但应先把不同数据来源的可信度写进统一模型，而不是把所有 provider 都包装成同一种“官方剩余量”。截至本报告日期，推荐结论如下：

1. **Codex 个人账户**：当前工作树通过本地 Codex 登录材料调用两个非公开 `wham` endpoint，可以读到账户 credits、可选使用窗口与 available reset credits，但它不是公开稳定契约。应继续标记为 `Experimental`，不硬编码五小时或周窗口，保留显式触发和严格 allowlist，并准备随时失效。
2. **Codex Enterprise**：官方 Analytics API 提供 workspace 聚合使用量，适合组织报表，但不是个人订阅的“剩余百分比”。
3. **Claude Pro/Max**：Claude Code 官方 `statusLine` JSON 已提供 5 小时和 7 天窗口的 `used_percentage` 与 `resets_at`。Dashis 可以通过一个用户明确启用的本地 bridge 获取经过白名单裁剪的快照，并计算 `remaining = 100 - used`。这是 Claude 个人订阅最合适的官方机器可读路径。
4. **Google AI 个人订阅**：本次官方资料核对没有发现可供第三方应用读取 Gemini Apps、Google AI Pro/Ultra 或 Antigravity 基础配额剩余量的公开 API。官方界面和 Antigravity `/credits` 可以显示余额，但自定义 status line JSON 不包含该余额。因此第一版应提供“手动查看”，不要抓 Cookie、网页 DOM、TUI 输出或私有 endpoint。
5. **Gemini API 项目**：对于 Google Cloud 项目，可以用 Cloud Quotas API 获取 limit，并用 Cloud Monitoring 的 `generativelanguage.googleapis.com/quota/.../{limit,usage}` 指标读取用量，再按相同 quota、model、method、limit name 和窗口推导 remaining。该值必须标记为 `Official derived`，并显示数据延迟。
6. **OpenRouter**：推荐新增 OAuth PKCE 连接方式，换取用户控制的 API key，再通过 `GET /api/v1/key` 读取 key 的 limit、usage 和 `limit_remaining`。账户级 credits、activity 和 beta analytics 仍需要 management key；当前实现还需修复负余额、reasoning token 重复统计、analytics schema 和截断处理。

最重要的产品原则是：**“用户已经在浏览器或某个 CLI 中登录”不等于 Dashis 已获得授权。** Dashis 只应使用 provider 明确公开的本地输出、OAuth 授权或用户主动提供的临时 key；不得复用浏览器 Cookie、系统凭据或未公开的登录态接口。

### 2. 数据来源分级

建议把来源级别纳入模型和 UI，避免用户把推导值或私有接口误认为官方余额：

| 级别 | 含义 | 示例 | UI 标签 |
|---|---|---|---|
| `officialDirect` | Provider 官方接口直接返回剩余值 | OpenRouter `/api/v1/key.limit_remaining` | Official |
| `officialDerived` | 官方 limit 与 usage 可组合推导 | Gemini API Cloud quota/monitoring | Official · Estimated |
| `officialLocalBridge` | 官方本地程序把字段传给用户命令 | Claude Code `statusLine.rate_limits` | Official · Local |
| `experimentalPrivate` | 当前可用，但不是公开稳定契约 | Codex 个人 `wham` endpoint | Experimental |
| `manualOnly` | 仅官方 UI/TUI 可查看，缺少公开机器接口 | Google AI 个人订阅 | Manual check |

每个 provider snapshot 还应包含 `observedAt`、`freshness`、`scope`、`warnings` 和 `partialFailures`。没有可信数据时应显示空态或手动检查状态，不能用计划上限、默认值或历史值伪造“剩余”。

### 3. 当前工作树审计

本节仅描述当前未提交工作树，不代表远端或已提交基线。

#### 3.1 当前分层

- [DashisProviderService.swift](../App/macOS/DashisProviderService.swift) 承担 URLSession 请求、endpoint 检查和 JSON 归一化。
- [DashisProviderStore.swift](../App/macOS/DashisProviderStore.swift) 持有 provider 状态、临时输入和用户检查动作。
- [DashisModels.swift](../App/macOS/DashisModels.swift) 定义 Codex/OpenRouter 摘要与 provider 卡片值类型。
- [DashisDashboardComponents.swift](../App/macOS/DashisDashboardComponents.swift) 提供原生输入控件和显式检查按钮。
- [project.pbxproj](../Dashis.xcodeproj/project.pbxproj) 当前只有 macOS App target，没有 Swift test target。

`DashisProviderService.swift` 和 `DashisProviderStore.swift` 当前均为未跟踪文件；后续实现必须保留工作区已有改动，不能假设它们已经进入提交历史。

#### 3.2 Codex 当前实现

- 只有用户点击按钮后才读取本机 Codex auth，并调用 usage/reset credits；两个请求允许部分成功。
- 归一化层已经计算 `remainingPercent = 100 - usedPercent`，但 Store/UI 当前主要投影最高的 `usedPercent`，尚未把 remaining 作为统一主指标。
- Desktop 路径依赖两个非公开 `chatgpt.com/backend-api/wham/*` endpoint。即使当前有效，也应标为实验性，不能写成 OpenAI 官方公共 API。
- Enterprise Analytics 已有 workspace id、Bearer 请求和摘要处理，但没有完整分页循环。
- 官方资料确认个人用户应通过 Codex usage page/limit banner 查看计划限制；官方 Analytics API 则是 workspace 聚合指标，不是个人剩余量。参见 [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan) 与 [Codex Analytics API](https://learn.chatgpt.com/docs/enterprise/analytics-api)。

#### 3.3 OpenRouter 当前实现

- 已并发查询 credits、activity、analytics/query 和可选 generation，并允许部分结果成功。
- API key 目前是内存中的 `@Published String`，通过 `SecureField` 输入；源码未发现写入 `UserDefaults`、Keychain 或项目文件。
- `/analytics/meta` 已在源码 allowlist 中，但没有真正调用；现有 `docs/ARCHITECTURE.md` 与 `docs/DO_NOT_BREAK.md` 尚未记录该路径，形成源码/文档冲突。后续若实现调用，应以当前源码和官方文档为准，并同步更新项目文档与用户教程。
- 主要正确性风险：
  - `max(0, totalCredits - totalUsage)` 会丢失真实负余额。
  - `prompt + completion + reasoning` 会重复统计 reasoning，因为 OpenRouter 把 reasoning 作为 completion 的组成部分；官方 usage 还直接提供 `total_tokens`。
  - analytics 使用固定指标名，没有先读取 meta；响应只统计行数，没有处理 `metadata.truncated`。
  - 网络层使用 `URLSession.shared`，缺少明确的 ephemeral/no-cache 配置和重定向后的 allowlist 复核。

### 4. Provider 可行性矩阵

| Provider / 产品 | 目标指标 | 官方可用路径 | 自动读取 | 推荐结论 |
|---|---|---|---:|---|
| Codex 个人 ChatGPT 计划 | 账户 credits、可选服务端窗口、available reset credits | 官方 usage page/limit banner；无公开个人 quota API | 当前只能通过非公开路径 | 保留实验模式；不按 plan 或 slot 名推断固定周期 |
| Codex Enterprise | Workspace 使用量与活动 | Codex Analytics API | 是 | 官方组织级数据，不冒充个人剩余 |
| Claude Pro/Max + Claude Code | 5h、7d used/reset | `statusLine.rate_limits` | 是 | 本地官方 bridge，优先实施 |
| Claude API 组织 | API token/cost usage | Usage & Cost Admin API | 是 | 独立 provider scope，不等同 Pro/Max 订阅 |
| Google AI 个人订阅 / Gemini Apps | 模型或功能配额 | Gemini Apps/Antigravity 官方 UI | 否 | `manualOnly`，不抓取登录态 |
| Antigravity CLI | 基础配额与 AI credits | `/credits`、内置 statusline/Settings | 只可人工查看余额 | 自定义 statusline payload 无 credits 字段，不自动化 |
| Gemini API Google Cloud 项目 | RPM/TPM/RPD 等 | Cloud Quotas + Cloud Monitoring | 是，可推导 | `officialDerived`，显示延迟与窗口 |
| OpenRouter 普通用户 key | key limit、usage、remaining | OAuth PKCE + `GET /api/v1/key` | 是 | 推荐默认连接方式 |
| OpenRouter management key | 账户 credits/activity/analytics | `/credits`、`/activity`、analytics meta/query | 是 | 高级模式，权限更高，保持显式输入 |

### 5. Claude 推荐实现

#### 5.1 官方数据

Claude Code 会把一份 JSON 通过 stdin 传给用户配置的 status line command。对于 Claude.ai Pro/Max 订阅者，第一次 API 响应后可能出现：

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

每个窗口可能单独缺失，`rate_limits` 也可能完全缺失；`resets_at` 是 Unix epoch seconds。官方字段与缺失条件见 [Claude Code status line](https://code.claude.com/docs/en/statusline)。

Dashis 应计算：

```text
remainingPercentage = 100 - usedPercentage
```

这个计算属于对官方字段的确定性归一化，不需要读取 Claude OAuth token、Cookie、Keychain 或浏览器状态。

#### 5.2 本地 bridge

推荐新增一个用户明确启用的 bundled helper，例如 `dashis-claude-statusline`：

1. 用户在 Claude provider detail 中点击“Connect Claude Code”。
2. Dashis 检查是否已经存在 status line 配置，但不读取任何 Claude 凭据。
3. Dashis 展示将要写入的配置变化并要求确认；已有 status line 时必须提供链式/兼容方案，不能静默覆盖。
4. helper 从 stdin 接收 JSON，只解析上述四个 rate-limit 字段和采集时间。
5. 立即丢弃 cwd、session id、transcript path、仓库、模型、成本等无关字段。
6. 将净化后的 snapshot 通过本地 IPC 或原子写入的 `0600` 权限文件传给 Dashis；文件设置短 TTL。
7. helper 仍向 stdout 输出用户原有 status line 内容，避免破坏 Claude Code 体验。
8. Dashis 根据 `observedAt` 显示 Fresh/Stale。没有新 Claude 响应时不要把旧值当实时值。

不要为了刷新配额而自动发送 Claude 请求；这会产生实际用量。浏览器中已经登录 Claude.ai 也不够，用户需要在 Claude Code 中登录并产生至少一次响应，官方字段才可能出现。

#### 5.3 组织 API 的边界

Anthropic Usage & Cost Admin API 面向 Claude Platform 组织，需要 Admin 权限，并明确不适用于个人账户；它统计 API 组织用量与成本，不是 Pro/Max 个人订阅剩余量。参见 [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)。

### 6. Google AI 推荐实现

#### 6.1 个人订阅：只提供官方人工入口

Google AI Pro/Ultra、Gemini Apps 和 Antigravity 属于消费级订阅体验。本次官方文档核对没有发现第三方应用可调用的个人剩余配额 API。

- Gemini Apps 官方帮助页说明限制会随模型、功能、实验和容量变化，参见 [Gemini Apps limits](https://support.google.com/gemini/answer/16275805?hl=en)。
- Google 已公告：自 2026-06-18 起，Gemini Code Assist IDE extension 和 Gemini CLI 不再为 Individual、Google AI Pro/Ultra 消费账户提供请求，且消费账户不能继续用 Login with Google 访问这些旧入口，参见 [Gemini Code Assist consumer-account deprecation](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)。
- Antigravity 官方文档允许用户在 CLI 内查看 statusline、`/credits` 和 Settings 中的 quota/credits，参见 [Managing AI Credits & Quotas](https://antigravity.google/docs/cli-credits)。
- Antigravity 自定义 status line JSON 虽包含 `plan_tier` 和 context window，但官方字段表没有 quota/credits remaining，参见 [Antigravity status line customization](https://antigravity.google/docs/cli-statusline)。

因此 Dashis 第一版应：

- 显示 `Manual check required`。
- 提供说明“在 Antigravity CLI 输入 `/credits`”或打开官方 usage/settings 页的动作。
- 允许用户选择性录入一个仅供 UI 展示的手动余额和采集时间，但必须标为 `manual`，不能自动续用或伪装成实时值。
- 不读取 Google Cookie、Gemini/Antigravity 内部 OAuth 文件、浏览器 profile、系统 Keychain、TUI 屏幕输出或未公开 endpoint。

#### 6.2 Gemini API 项目：官方推导模式

对于 Gemini API 对应的 Google Cloud project，可以创建第二种 provider scope：`geminiAPIProject`。

建议流程：

1. 使用 macOS `ASWebAuthenticationSession` 发起 Google OAuth；浏览器已登录只会减少登录步骤，不代表授权已经自动完成。
2. 第一版只在内存中保留 access token。若未来要持久化 refresh token 到 Keychain，必须先作为单独的凭据政策变更评审。
3. 让用户选择 project；请求最小 IAM 权限，Cloud Quotas 查询至少需要 `cloudquotas.quotas.get`，官方 REST 接口使用 `cloud-platform` scope。
4. 调用 Cloud Quotas `projects.locations.services.quotaInfos.list` 获取项目在 `generativelanguage.googleapis.com` 下的有效 quota 信息。官方接口见 [quotaInfos.list](https://docs.cloud.google.com/docs/quotas/reference/rest/v1/projects.locations.services.quotaInfos/list)。
5. 调用 Cloud Monitoring 读取对应 `generativelanguage.googleapis.com/quota/.../limit` 和 `/usage` time series；这些指标通常带 `limit_name`、`model`，usage 还可带 `method`，并可能有约 150 秒可见性延迟。指标目录见 [Google Cloud metrics](https://docs.cloud.google.com/monitoring/api/metrics_gcp_d_h#generativelanguage)。
6. 只有在 metric、limit name、model、method、location 和时间窗口能可靠对齐时才计算：

```text
remaining = limit - usageInMatchingWindow
remainingPercentage = remaining / limit * 100
```

7. 不要把负数强制变成 0；应保留原始值，并额外给出 `isExceeded`。
8. 对 RPD 使用 Google 官方定义的太平洋时间午夜重置；RPM/TPM 使用对应滚动或固定短窗口。规则见 [Gemini API rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)。
9. 当 active limit 无法与 usage 对齐、指标处于 ALPHA/BETA、存在动态容量，或监控数据尚未到达时，显示 `Estimated`/`Unavailable`，不能猜测。

### 7. OpenRouter 推荐实现

#### 7.1 默认连接方式：OAuth PKCE

OpenRouter 官方 OAuth PKCE 可以把已登录用户带到授权页，并用授权 code 换取一个用户控制的 API key。Localhost callback 可使用任意端口，适合原生本地应用。官方流程见 [OAuth PKCE](https://openrouter.ai/docs/guides/overview/auth/oauth)。

推荐步骤：

1. 生成高熵 `code_verifier`，使用 SHA-256 生成 S256 `code_challenge`。
2. 用 `ASWebAuthenticationSession` 或 loopback localhost callback 打开 `https://openrouter.ai/auth`。
3. 校验 callback state、host、path 和一次性 code；`code_verifier` 只保存在内存中。
4. 通过 `POST https://openrouter.ai/api/v1/auth/keys` 交换用户控制的 key。
5. key 默认只保存在当前 app session；退出、Clear 或 OAuth state 失效后清除。
6. 使用该 key 调用 `GET https://openrouter.ai/api/v1/key`。官方响应直接定义 `limit`、`usage`、`limit_remaining`、`limit_reset`、`expires_at` 等字段，参见 [Get current API key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key)。

对普通用户来说，这比要求手工复制 management key 更低权限，也更符合“已登录后明确授权 Dashis”的目标。

#### 7.2 高级账户级模式

当用户确实需要账户总 credits、过去 30 天 activity 或 beta analytics 时，再显示高级 management-key 模式：

- `GET /api/v1/credits` 返回 `total_credits` 与 `total_usage`，management key required，参见 [Get remaining credits](https://openrouter.ai/docs/api/api-reference/credits/get-credits)。
- `GET /api/v1/activity` 返回过去 30 个已完成 UTC 日按 endpoint 聚合的 activity，参见 [Get user activity](https://openrouter.ai/docs/api/api-reference/analytics/get-user-activity)。
- 先调用 `GET /api/v1/analytics/meta` 获取当前 metrics、dimensions、operators 和 granularities，参见 [Analytics meta](https://openrouter.ai/docs/api/api-reference/beta-analytics/get-analytics-meta)。
- 再调用 `POST /api/v1/analytics/query`，并处理 `metadata.row_count`、`metadata.truncated` 与超时，参见 [Query analytics data](https://openrouter.ai/docs/api/api-reference/beta-analytics/query-analytics)。

#### 7.3 当前实现的必要修正

1. 优先使用 provider 返回的 `limit_remaining` 或原始 `total_credits - total_usage`，不要把负余额钳成 0。
2. token 总量使用官方 `total_tokens`；没有该字段时使用 `prompt_tokens + completion_tokens`。不要再额外加 `reasoning_tokens`，因为 reasoning 属于 completion/output breakdown。参见 [OpenRouter usage schema](https://openrouter.ai/docs/api/reference/overview)。
3. analytics query 由 meta 驱动，不在源码中永久假设 metric 名称。
4. `metadata.truncated == true` 时，UI 显示不完整警告，并调整 `group_limit`/`limit` 或缩小窗口后重试。
5. 为 credits、activity、analytics、generation 分别保留 partial failure，不让一个失败抹掉其他有效数据。

### 8. 统一架构建议

#### 8.1 Provider client

将当前单体 Service 拆成 provider adapter，同时保留一个共享的安全 HTTP 层：

```swift
protocol ProviderUsageClient {
    var providerID: ProviderID { get }
    func fetchSnapshot(context: ProviderContext) async -> ProviderSnapshot
}
```

建议模块：

```text
DashisProviderStore
  -> CodexUsageClient
  -> ClaudeUsageClient
  -> GoogleConsumerUsageClient
  -> GeminiAPIProjectUsageClient
  -> OpenRouterUsageClient

Shared
  -> ProviderHTTPClient
  -> EndpointPolicy
  -> ProviderSnapshot / QuotaWindow
  -> FreshnessPolicy
  -> CredentialSession
```

`ProviderHTTPClient` 应使用 ephemeral `URLSessionConfiguration`，关闭 URL cache、限制 redirect，并在每次 redirect 后重新执行 scheme/host/path/query allowlist。错误日志只记录 provider、状态码、错误类别和 request correlation id，不记录 Authorization、query 中的敏感值或完整响应 body。

#### 8.2 统一值类型

建议核心模型至少包含：

```swift
struct ProviderSnapshot {
    let providerID: ProviderID
    let scope: ProviderScope
    let sourceKind: UsageSourceKind
    let observedAt: Date
    let windows: [QuotaWindow]
    let balance: ProviderBalance?
    let warnings: [ProviderWarning]
    let partialFailures: [ProviderFailure]
}

struct QuotaWindow {
    let id: String
    let label: String
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let usedPercentage: Double?
    let remainingPercentage: Double?
    let resetsAt: Date?
    let isEstimated: Bool
}
```

不要只保存卡片文案。Provider client 应先返回结构化 snapshot，再由 Store 统一选择“最紧迫窗口”作为主卡指标。

#### 8.3 UI 语义

四张 provider 卡都采用相同层级：

- 主指标：最紧迫的 remaining window 或余额。
- 次指标：used/limit、reset time、计划或 project scope。
- 来源 badge：Official、Estimated、Local、Experimental 或 Manual。
- 新鲜度：`Updated now`、`Stale`、`No data`。
- 警告：部分失败、数据延迟、需要重新授权或需要人工查看。

Google consumer 卡没有机器数据时，应保持“Manual check required”，而不是为了视觉一致而生成百分比。

### 9. 分阶段实施路线

#### Phase 0：统一模型与安全网络层

- 引入 `ProviderSnapshot`、`QuotaWindow`、来源级别和 freshness。
- 将当前 Codex 标记为 `experimentalPrivate`。
- 创建 ephemeral HTTP client、redirect revalidation、统一错误脱敏和重试/backoff。
- 为现有 provider 添加 fixture-based decoder 与 allowlist 测试。

完成标准：当前 Codex/OpenRouter UI 行为可保持，但底层已返回结构化 snapshot；测试不访问真实账户。

#### Phase 1：修复 OpenRouter，再增加 OAuth

- 修复负余额、token 重复统计、analytics meta/truncated。
- 添加 OAuth PKCE 与 `/api/v1/key` 默认模式。
- 保留 management key 作为高级模式，并明确权限差异。

完成标准：普通用户无需复制 management key即可查看 key-level remaining；高级模式保持 session-only。

#### Phase 2：Claude 本地 bridge

- 新增 Claude provider、5h/7d windows 和 status line helper。
- 提供配置预览、已有 status line 兼容、最小字段白名单和 stale TTL。
- 不主动生成 Claude 请求刷新数据。

完成标准：Claude Code 正常产生响应后，Dashis 可显示两类窗口；移除/禁用 bridge 后 Claude Code 原状态恢复。

#### Phase 3：Google 双模式

- `googleConsumer`：只提供官方人工查看入口与可选手动快照。
- `geminiAPIProject`：OAuth、project 选择、Cloud Quotas、Monitoring 和 derived quota windows。

完成标准：UI 能清晰区分“个人订阅手动查看”和“Cloud project 官方推导”，不会把两者合并成同一余额。

#### Phase 4：统一 UX、测试与文档

- Dashboard 固定展示 Codex、Claude、Google AI、OpenRouter。
- 增加 Swift test target、provider fixtures、安全日志测试和 partial failure 测试。
- 更新 `CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md`、`DO_NOT_BREAK.md`、`TESTING.md` 和 `USER_TUTORIAL.md`。

完成标准：四家 provider 的来源级别、权限、刷新方式和故障状态均可由用户理解并验证。

### 10. 凭据与隐私边界

必须保持：

- 所有真实检查由用户显式触发；只有本地 status line bridge 可在用户已启用后被事件驱动更新。
- API key、OAuth access token、PKCE verifier 默认只在内存中存在。
- 不写日志、fixture、文档、错误文本或 analytics。
- 不读取 Cookie、浏览器 profile、系统 Keychain、第三方 CLI 私有 token 文件或完整 provider 响应。
- 只保存结构化、白名单化、无账号标识的 usage snapshot。
- endpoint allowlist 同时验证 HTTPS、精确 host、path、method、query 名称与 redirect 目标。
- `Clear` 必须覆盖所有临时 key、OAuth state、verifier、输入字段和内存 snapshot。

如果未来决定跨启动持久化 OpenRouter/Google refresh token，应另行设计 Keychain access group、可撤销流程、迁移和删除验证；不能把这一步混入普通 provider 实现。

### 11. 测试与验收建议

#### 单元测试

- Claude：`rate_limits` 缺失、单窗口缺失、null、边界 0/100、epoch reset、stale TTL。
- Google：quota/usage 精确维度匹配、跨窗口、监控延迟、分页、无 matching limit、负 remaining。
- OpenRouter：`limit_remaining`、负 credits、reasoning 不重复、meta schema、`truncated`、partial failure。
- Codex：当前 decoder、两个请求一成一败、私有 endpoint 失效时 fail closed。
- 共用网络层：非 HTTPS、错误 host、trailing slash、未知 query、跨域 redirect、错误 method 全部拒绝。

#### 安全测试

- 日志扫描不出现 Bearer、key、code、verifier、账号 id 或完整 body。
- fixture 仅使用合成字段，不保存真实响应。
- 清除和 app 退出后内存凭据不可再次使用。
- Claude bridge 的净化快照不包含 cwd、session、transcript、email 或仓库信息。

#### 手动验收

- 未授权时四张卡都显示诚实空态。
- Claude 有新响应后更新；没有新响应时正确变 stale。
- Google consumer 只出现人工查看入口。
- Gemini project 显示 project scope、估算标签和数据延迟。
- OpenRouter OAuth 取消、拒绝、code 重放和 key 过期都有明确错误。
- Codex 私有接口失败不会触发登录刷新、重置或任何写操作。

### 12. 官方资料索引

#### OpenAI / Codex

- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [Codex Analytics API](https://learn.chatgpt.com/docs/enterprise/analytics-api)

#### Anthropic / Claude

- [Claude Code status line](https://code.claude.com/docs/en/statusline)
- [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)

#### Google

- [Gemini Apps limits](https://support.google.com/gemini/answer/16275805?hl=en)
- [Gemini Code Assist consumer-account deprecation](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)
- [Antigravity AI credits](https://antigravity.google/docs/cli-credits)
- [Antigravity custom status line](https://antigravity.google/docs/cli-statusline)
- [Gemini API rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)
- [Cloud Quotas quotaInfos.list](https://docs.cloud.google.com/docs/quotas/reference/rest/v1/projects.locations.services.quotaInfos/list)
- [Cloud Monitoring generativelanguage metrics](https://docs.cloud.google.com/monitoring/api/metrics_gcp_d_h#generativelanguage)

#### OpenRouter

- [OAuth PKCE](https://openrouter.ai/docs/guides/overview/auth/oauth)
- [Get current API key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key)
- [Get remaining credits](https://openrouter.ai/docs/api/api-reference/credits/get-credits)
- [Get user activity](https://openrouter.ai/docs/api/api-reference/analytics/get-user-activity)
- [Analytics meta](https://openrouter.ai/docs/api/api-reference/beta-analytics/get-analytics-meta)
- [Query analytics data](https://openrouter.ai/docs/api/api-reference/beta-analytics/query-analytics)
- [Usage schema](https://openrouter.ai/docs/api/reference/overview)

## DOCS_CONTENT_SUMMARY

- `/Users/vita/Vitemis/AGENTS.md`：确认 Codex 可写 `codex-report/`，并规定时间戳文件名和报告必需章节。
- `docs/CURRENT_STATE.md`：确认当前为 macOS SwiftUI provider-first dashboard，已有 Codex/OpenRouter 原生检查和 session-only 凭据边界。
- `docs/PROJECT_MAP.md`：确认源码、Xcode scheme、Run action 和用户教程位置。
- `docs/ARCHITECTURE.md`：确认 Store → Service → allowlisted endpoint 链路及当前未确认的后端、存储、iOS 边界。
- `docs/DO_NOT_BREAK.md`：确认不得放宽 allowlist、不得持久化 key/token、不得读取或输出凭据。
- `docs/TESTING.md`：确认文档任务至少运行 `git diff --check` 与 `git status --short`；当前尚无 Swift test target。
- `docs/NEXT_TARGET.md`：当前 active target 为 none。

本轮只新增研究报告，没有改变启动、构建、UI、provider 接入、凭据处理、endpoint allowlist、验证或排障流程，因此无需同步修改 `docs/USER_TUTORIAL.md` 或其它长期状态文档。真正实施任一 Phase 时必须同步更新这些文档。

## VALIDATION_RESULT

- 已执行 `pwd`，结果为 `/Users/vita/Vitemis/Dashis`。
- 已执行 `git rev-parse --show-toplevel`，结果为 `/Users/vita/Vitemis/Dashis`。
- 已执行 `git status --short -- .`，确认并保留用户已有改动。
- 已完整阅读项目要求的父级 Agent 规范以及 `CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md`、`DO_NOT_BREAK.md`、`TESTING.md`、`NEXT_TARGET.md`。
- 已只读复核当前 provider Service、Store、Models、UI 控件与 Xcode target 现状。
- 已使用官方一手资料复核 Codex、Claude、Google 与 OpenRouter 能力边界。
- 2026-07-10 的 OpenAI Codex manual helper 在普通和获批联网环境均因网络错误失败；当时官方 Docs MCP 未安装，因此报告改用 OpenAI 官方 Help/Developer Learn 页面作为只读安全回退来源。2026-07-15 已在获批后注册 OpenAI Developer Docs MCP；需要重启 Codex 后才会在新会话中可调用，本次额度修订仍使用官方 Help 页面复核。
- 已运行 `git diff --check`，当前工作树已跟踪文件无空白错误。
- 已对新增未跟踪报告运行 `git diff --no-index --check /dev/null <report>`；首次发现标题区 Markdown 硬换行的尾随空格并已修正。复查无空白诊断；退出码 1 仅表示新增文件与 `/dev/null` 存在预期差异。
- 已检查报告关键章节和最终 `git status --short -- .`，新增范围仅为 `codex-report/`。
- 未运行构建/测试：本轮仅新增 Markdown 研究报告，没有修改可执行代码、工程配置或测试源码。

## UNCERTAINTIES

1. Google 个人订阅没有被本次官方资料证明存在第三方机器可读余额接口；未来如 Google 发布正式 API，应重新研究，而不是沿用网页/TUI 抓取。
2. Codex 个人 `wham` endpoint 不是公开稳定契约，字段、权限或路径可能随时变化。
3. Claude `rate_limits` 依赖 Claude Code 版本、Pro/Max 订阅与会话至少一次响应；它不是独立的远程刷新 API。
4. Gemini API quota 指标目前包含 ALPHA/BETA 项，且监控数据有可见性延迟；具体 metric/limit matching 必须使用目标 project 的真实 metadata 验证。
5. OpenRouter beta analytics schema 可变化，必须依赖 meta 和响应 metadata，而不是固定 fixture。
6. OAuth token 是否允许跨启动持久化仍未被项目政策批准；本方案默认 session-only。
7. 当前 Service/Store 是未跟踪工作树文件，后续落地前需先明确与用户现有改动的合并边界。

## NEXT_RECOMMENDED_ACTION

先实施 **Phase 0（统一 snapshot/来源模型、安全网络层和 Swift test target）**，然后完成 **Phase 1（OpenRouter 正确性修复与 OAuth PKCE）**。这两步会为 Claude 和 Google 提供稳定基座，并先消除当前可确认的数据错误风险。未经新的实现请求，不自动继续修改业务源码。

## 实现结果与经审计偏差

> 更新日期：2026-07-11（Asia/Singapore）
>
> 本节记录该研究建议在当前未提交工作树中的实际落地结果。报告开头“本报告不代表能力已经实现”、第 3 节旧工作树审计、原 `DOCS_CONTENT_SUMMARY` 与 `NEXT_RECOMMENDED_ACTION` 是 2026-07-10 研究时的历史状态；理解当前实现时以本节、当前源码、Xcode 工程和 `docs/` 项目文档为准。

### 2026-07-15 Codex 额度语义修订

OpenAI 当前官方说明把 Codex、ChatGPT Work、ChatGPT for Excel 与 Workspace Agents 视为共享 agentic usage/credit pool；消耗量随任务大小、复杂度、模型和运行位置变化。官方 rate card 也记录了 2026 年 4 月起多类计划转向 token-based credit consumption。与此同时，部分官方计划说明仍可能出现具体 rolling-window 示例，因此本项目不能把“所有账户都有五小时限制”或“所有账户都没有任何固定窗口”写成全局常量；当前账户的官方 usage page/limit banner 和服务端实际响应才是最终依据。来源：[Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan/)、[Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card-2)。

据此采用以下实现：

- 删除 Codex personal decoder 中 `primary_window -> 5h`、`secondary_window -> weekly` 的角色硬编码。
- 只为 payload 实际给出的窗口建模；有效 `limit_window_seconds` 转成对应 hour/day/minute/second 标题，缺失或非法 duration 使用通用槽位标题。
- 接受只有 credits 或只有 windowless rate-limit 状态的响应；解析 `credits.balance`、`credits.unlimited` 与 `credits.has_credits`，并把服务端明确的 `unlimited=true` 限定为当前账户状态。
- `/rate-limit-reset-credits` 的 available count 单独显示为 `Available reset credits`，不与通用 Codex credit balance 或已执行 reset 次数混淆。
- UI、教程、测试和不可破坏约束统一要求：不按 plan、primary/secondary 槽位或历史产品规则推断固定周期。

### 已落地范围

- Dashboard 与 Sidebar 固定为 Codex、Claude、Google AI、OpenRouter 四个内置 provider；旧动态 Add/custom provider UI 已移除。
- 已新增统一 `ProviderSnapshot` / `QuotaWindow` / source / freshness / warning / partial-failure 模型，以及 snapshot 到卡片/详情的投影。negative remaining 保留原值，只有进度条被限制。
- 已把原单体 provider service 拆为 Codex、Claude、Google consumer、Gemini project、OpenRouter adapter；`DashisProviderService` 只保留 composition-root 职责。
- 已新增 ephemeral/no-cookie/no-cache HTTP client、8 MiB response cap、redirect 拒绝、幂等请求有限 retry，以及精确 host/path/method/query/body allowlist。
- Xcode 工程已增加 `ClaudeStatusLineHelper` 与 `DashisTests` target；helper product 嵌入 App，shared `Dashis` scheme 包含测试 target。
- 已增加只使用合成 fixture 的 Swift tests，覆盖 endpoint policy、decoder、freshness、negative remaining、OAuth/PKCE、Claude settings/snapshot 与 Google quota derivation 等边界。完成状态应以当前代码最后一次 `xcodebuild test` 与 Debug build 的实际输出为准，不沿用本报告旧验证章节中的测试现状描述。

### 经审计后采用的实现差异

1. **OAuth 浏览器承载**：研究阶段曾建议 `ASWebAuthenticationSession`。当前 macOS 实现改为用 `NSWorkspace` 打开系统默认浏览器，并由 `NWListener` 接收 installed-app loopback callback。两家 provider 都使用随机端口和高熵随机 callback path，listener 只绑定 `127.0.0.1`，不绑定 `localhost`、IPv6 或外部接口。
2. **OpenRouter 官方 OAuth 没有 `state` 参数**：研究建议中“校验 callback state”不适用于当前官方 OpenRouter OAuth 契约。实现严格只发送官方定义的 `callback_url`、`code_challenge`、`code_challenge_method=S256`；授权会话隔离依赖随机一次性 callback path、精确 path 校验、loopback-only listener、PKCE verifier 与一次性取消语义。Google OAuth 仍生成并验证 state。
3. **Google project 由用户手工指定**：研究路线中的“让用户选择 project”没有实现成项目枚举。当前 UI 要求输入 project ID 或 project number，再以最小 `cloud-platform` OAuth scope 查询该项目；这样没有额外引入 Resource Manager project-list endpoint 或更宽的数据发现范围。
4. **Claude Preview 的本地写入边界**：经最终审计，`Preview connect` 只验证 bundled helper、读取安全 settings 并生成字段级 patch 摘要，不安装文件或修改 settings。只有第二步 `Apply change` 才安装/更新私有 helper，并在 fingerprint 复核后写 settings；Cancel 无持久改动。
5. **OpenRouter analytics 截断处理**：实现读取 `/analytics/meta`，只选择服务端声明为非 rate 的可加总 metric/dimension。`metadata.truncated` 时自动把时间窗缩小一半重试一次；UI 明确说明结果采用较窄窗口，重试仍截断或失败时继续标为不完整，不把它伪装成原窗口完整总计。
6. **OpenRouter rate/总量语义**：经正确性审计后，只汇总定义为可加总的 count、token 与 usage。不同日期、模型或 endpoint 的 rate 不相加成一个账户总 rate。token total 优先官方 `total_tokens`，缺失时使用 prompt + completion；reasoning 仅显示为 output breakdown，不再重复计入。
7. **OpenRouter Clear 的服务端边界**：Clear 会取消本地 OAuth task/listener并清除 key、verifier、输入和 snapshot，但无法保证撤销已经由 `/api/v1/auth/keys` 在服务端创建的 key。浏览器已批准后若 App 状态不确定，用户必须在 OpenRouter 官方账户/API keys 页面 revoke。
8. **Google consumer 与 Antigravity**：Consumer mode 只打开 Gemini 官方页面或记录带时间的 manual reading；Antigravity quota/credits 继续由用户在其 CLI 输入 `/credits` 人工查看。实现不抓 DOM、Cookie、TUI、browser profile、Keychain 或私有 OAuth 文件。
9. **Google Cloud 推导的保守约束**：Project mode要求授权主体具备 `cloudquotas.quotas.get` 与 `monitoring.timeSeries.list`。实现按 quota ID、`limit_name`、声明 dimension/model/location 和 metric type 精确匹配，region/zone 可精确映射到 Monitoring location；按 Cloud Quotas 返回的 `dimensionsInfos` specificity 顺序把每条 series 只分配一次，Cloud Quotas 与 Monitoring limit 冲突或 cadence 未知时 remaining unavailable。支持官方 `minute`/`hour`/`day` cadence 字符串；Monitoring FULL point 分页会按完整 labels 合并。由于短窗 DELTA 离散采样且约延迟 150 秒，minute/hour 只展示最新完整可见历史窗，并在 window label/warning 标 exact as-of，不冒充请求时刻的实时 remaining。用户可输入逗号/空白分隔的 exact quota IDs，留空自动选择最多 24 个 definition。
10. **凭据生命周期**：Google access token、OpenRouter OAuth/management key、Codex Enterprise analytics key、OAuth code/state/verifier 都保持 session-only。Google token exchange 不使用 client secret，并丢弃 refresh token 与 ID token；当前没有引入 Keychain 持久化。
11. **Claude freshness 加固**：缺少 `rate_limits` 不覆盖旧 snapshot；单窗口可独立更新；完全相同的窗口不会因为非响应 statusLine 事件而刷新 `observedAt`。Dashis 仍不自动发送 Claude 请求。
12. **网络失败语义**：远端 redirect 一律拒绝；OAuth/token POST 不自动重试，只有幂等 GET/HEAD 可对有限瞬时错误重试一次。adapter 对不支持的 200 响应 schema 保持 fail closed，并只向 UI 提供净化错误摘要。

### 当前操作与安全边界

- Codex personal 继续标为 `Experimental`；Enterprise Analytics 继续标为官方 workspace usage，不冒充个人订阅 remaining。
- Claude 使用用户显式启用的 statusLine bridge；Disconnect 恢复原 command，Clear loaded data 只删除净化 snapshot。
- Google consumer 是 `Manual check`；Gemini project 是 `Official · Estimated`，并明确 IAM、dimension matching 与 Monitoring delay。
- OpenRouter 默认使用低权限 OAuth-created key 的 `/api/v1/key`；management key 只在 Advanced mode 显式输入。
- 自动测试、fixture、日志和文档不读取或保存真实 `~/.codex`/`~/.claude` 内容、API key、token、Cookie、完整 provider 响应或账号数据。

### 最终验证结果

- `xcodebuild ... test`：成功，73/73 个离线合成测试通过；新增边界包括 Codex credit-only/windowless/dynamic-window 语义，以及手工 quota 极端有限值不能推导出 infinity。
- `xcodebuild ... build`：macOS Debug build 成功；`dashis-claude-statusline` 已嵌入 App 的 `Contents/MacOS/`。
- `plutil -lint Dashis.xcodeproj/project.pbxproj` 与 `xcodebuild -list -project Dashis.xcodeproj`：通过；三个 target 与 shared schemes 可发现。
- `git diff --check`：通过。
- 临时 `docs/NEXT_TARGET.md` 已在目标完成后按项目规则删除；长期事实已回写到 `docs/` 其余项目文档与本附录。
- `script/build_and_run.sh --verify`：2026-07-15 复验成功；脚本完成 Debug build、LaunchServices 注册并确认 Dashis 进程保持运行。2026-07-11 的未授权记录只代表当时验证环境，不是 Codex 账户额度结论。
- 未使用真实 provider 凭据做端到端验证；IAM、线上 response schema、预览指标和账户特定 quota 仍需用户显式授权后人工验收。

独立安全收口审计未发现仍成立的 P1/P2 blocker。已知非阻塞 caveat：Google minute/hour 是带 exact as-of 的历史估算；OpenRouter Clear 不撤销服务端 key；Claude Apply 若 settings 写入失败可能留下未启用 helper；Claude settings fingerprint 复核与最终 rename 之间仍有极窄的同用户并发窗口，属于后续 P3 加固项。
