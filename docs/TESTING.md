# TESTING

## 当前测试面

Dashis 当前有三个 Xcode target：

- `Dashis`：macOS SwiftUI App。
- `ClaudeStatusLineHelper`：产物名 `dashis-claude-statusline`，嵌入 App 的 `Contents/MacOS`。
- `DashisTests`：由 shared scheme `Dashis` 的 Test action 运行，test host 为构建后的 Dashis App。

测试源码位于：

```text
tests/DashisTests/ProviderFoundationTests.swift
tests/DashisTests/ProviderDecoderTests.swift
tests/DashisTests/ProviderCorrectnessTests.swift
tests/DashisTests/SecurityBoundaryTests.swift
```

自动测试必须使用合成 fixture、离线运行且不读取真实账户。当前没有 Web/Node 测试入口、package manager、lint/format 工具或 iOS test target。

## 推荐的完整验证顺序

从仓库根目录执行。为了避免生成物进入仓库，示例把 DerivedData 放到系统临时目录：

```sh
pwd
git rev-parse --show-toplevel
git status --short -- .
plutil -lint Dashis.xcodeproj/project.pbxproj
xcodebuild -list -project Dashis.xcodeproj
xcodebuild \
  -project Dashis.xcodeproj \
  -scheme Dashis \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${TMPDIR%/}/dashis-tests-derived-data" \
  test
xcodebuild \
  -project Dashis.xcodeproj \
  -scheme Dashis \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${TMPDIR%/}/dashis-build-derived-data" \
  ENABLE_DEBUG_DYLIB=NO \
  build
./script/build_and_run.sh --verify
git diff --check
git status --short -- .
```

验收标准：

- `pwd` 与 Git root 都是 `/Users/vita/Vitemis/Dashis`，且没有清理或覆盖用户已有改动。
- `plutil` 通过；`xcodebuild -list` 能发现 `Dashis`、`ClaudeStatusLineHelper`、`DashisTests` 和 shared scheme `Dashis`。
- Test action 0 failure。测试数量会随安全回归用例增长，不把固定数量当成契约。
- Debug build 通过；`Dashis.app/Contents/MacOS/dashis-claude-statusline` 存在并可由 `Bundle.url(forAuxiliaryExecutable:)` 找到。
- `--verify` 能通过 LaunchServices 启动 App，并确认 `Dashis` 进程保持运行。
- `git diff --check` 无空白错误；最终状态只包含任务范围内预期变更和明确保留的用户已有改动。

## 本地 build/run

常规构建并打开：

```sh
./script/build_and_run.sh
```

构建、打开并验证进程：

```sh
./script/build_and_run.sh --verify
```

脚本会停止旧的 `Dashis` 进程，使用 `ENABLE_DEBUG_DYLIB=NO` 构建 Debug App，在临时 DerivedData 中准备 bundle xattr，然后通过 `/usr/bin/open -n` 打开。Codex App 的 Run action 调用同一个脚本。

其它脚本 mode：

```sh
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

`--debug` 进入 LLDB；`--logs` 读取 Dashis 进程日志；`--telemetry` 同时过滤 Dashis 进程和 `com.Vita0818.DashisMac` subsystem。日志验证不得包含真实 token、API key、OAuth code/verifier、账号标识或完整 provider body。

### Debug 视觉 QA fixture

完成 Debug build 后，可直接用 launch argument 打开合成的 Codex detail：

```sh
/usr/bin/open -n \
  "${TMPDIR%/}/dashis-build-derived-data/Build/Products/Debug/Dashis.app" \
  --args --visual-qa
```

`--visual-qa` 只在 Debug 生效：它注入合成 quota、credit、reset-credit 与 warning，并自动选择 Codex route，便于验证两列卡片、进度、折叠层级和 light/dark 截图。fixture 初始化不读取账户文件、credential、真实 provider response，也不自动发起网络请求；Release 不启用。它只证明视觉布局，不证明 decoder、endpoint 或真实账户数据正确。

## 自动测试覆盖要求

### Provider foundation

- 固定四 provider registry、scope/source/freshness 与 no-data 行为。
- snapshot 到摘要与类型化详情卡片的投影；返回窗口优先、credit-only 不虚构窗口、OpenRouter 重复 balance/window 去重、negative remaining 保留。只有 percentage 或可验证 numerator/positive denominator 才生成 progress，未知 denominator 不退化为 `0%`。
- 安全 JSON 数值/布尔/日期转换；非有限值、错误类型和过大整数 fail closed。
- endpoint policy 拒绝非 HTTPS、错误端口、lookalike host、embedded credentials、fragment、trailing slash、dot segment、重复/未知 query、错误 method/content type/body。
- ephemeral HTTP client 拒绝 redirect、限制 response size，只对幂等请求执行有限 retry。
- PKCE verifier/challenge 格式与 loopback callback 约束。

### Codex

- personal usage credits、可选 windows 与 reset credits decoder；credit-only/windowless 响应可用，缺少任何可识别 usage/credit envelope 时 fail closed。
- 窗口标题必须跟随实际 `limit_window_seconds`；slot 名不能决定时长，缺失/非法 duration 使用通用标题，不能虚构 5 小时或周窗口。
- `balance`、`unlimited`、`has_credits=false` 的投影保持原意；账户 credits 与 available reset credits 分开。
- usage 与 reset 一成一败时保留 partial result。
- Enterprise aliases、分页 token、重复/非法 token、最多 100 页和错误 envelope。
- 本地 auth 文件的 symlink、所有者、权限与 1 MiB 上限保护；测试必须使用临时合成文件，不能读真实 `~/.codex/auth.json`。

### Claude

- 缺少/null `rate_limits`、单窗口、0/100 边界、越界百分比、秒/毫秒 epoch 和 future/stale/expired。
- 相同窗口事件不能刷新 `observedAt`；单窗口更新保守保留另一窗口。
- snapshot 普通文件、UID、0600、8 KiB、schema 与 symlink 保护。
- Connect/Disconnect patch 恢复 prior statusLine、duplicate key、并发 fingerprint 和权限保护。
- helper 端到端保持原 stdin/stdout/stderr/exit status；测试输入必须是合成 JSON，且不能写默认用户 snapshot。

### Google AI

- Consumer manual 空态不虚构 quota；手动值与 manual freshness。
- OAuth 仅有 `cloud-platform` scope、state + PKCE、严格 `127.0.0.1` callback、token body 无 client secret、refresh/ID token 不保存。
- Cloud Quotas 与 Monitoring decoder 的分页与 fail-closed 行为。
- quota ID / `limit_name` / model / location / dimension 精确匹配；更具体维度不能与默认 bucket 重复计数。
- DELTA 最新完整历史窗与 exact as-of、region/zone→location、concurrent GAUGE 最新值、limit 冲突、错误 metric type、未知 cadence、negative remaining。
- RPD 使用 `America/Los_Angeles` 日历午夜。

### OpenRouter

- `/key` 直接 `limit_remaining` 与负值；credits 的负 `total_credits - total_usage`。
- OAuth 授权参数不包含未被官方契约定义的 state；随机 callback path + PKCE 的约束。
- activity/generation 的 `total_tokens` 优先；fallback 只用 prompt + completion，reasoning 不重复相加。
- rate/非可加总 metric 不跨 row 伪造总和。
- analytics meta-driven metric/dimension、metadata row count、`truncated` 警告与非法 schema。
- credits/activity/analytics/generation partial failure 相互隔离。
- `Clear` 或 mode switch 后，迟到响应不能恢复已清除 key/snapshot。

## 手动 UI 验收

### 全局

- Sidebar 恰好显示 Dashboard、Codex、Claude、Google AI、OpenRouter；没有 Settings 或 Add provider。旧 SceneStorage 中的 Settings selection 必须自动回到 Dashboard。
- 用旧版 Dashis 截图做外壳基准：品牌应为 28 pt serif、页标题为 32 pt serif；Sidebar 列宽为 min 176 / ideal 218，导航约 14 pt serif、约 40 pt 行距并使用浅蓝选中态。详情区应保持 horizontal 30 / top 26 / bottom 30 外边距、14 pt 纵向 spacing、provider 内容最大宽度 900 与外层最大宽度 1180。
- Codex Analytics 参考图只用于核对 quota/balance 的主次层级、进度和去重；若视觉回归显示字体、Sidebar、字号、位置或间距被整体替换，即使信息内容正确也判定为失败。
- Dashboard 以带分隔线的扁平列表恰好显示四条紧凑摘要；没有 v0.1 mock telemetry、runs、WebView、网页、Node gateway、统计小卡墙或逐行套框。
- 中性空态每条摘要只显示 provider 名称、主值和一个主动作；不显示 kind、source/freshness、辅助统计或解释小字。真实实验/推导/手动数据与 historical/stale/expired/partial/failed/exceeded/warning 只显示一个准确限定词。
- provider route 无 snapshot 时没有占位明细、重复主值、默认说明或无状态可清的 Clear，有本地状态后 Clear 才出现；有 snapshot 时主要 quota/balance 或 KPI 在两列主卡片中展示，当前最小 App 布局仍保持两列。只有未来布局约束不足时才允许一列。
- 卡片只在 percentage 或 numerator/positive denominator 可验证时显示进度；limit-only、未知 denominator 与普通 KPI 不得出现伪造 `0%`。额外 quota/metric 与 source/scope/observed metadata 默认折叠。
- warning 与 partial failure 不套额外卡片，各完整出现一次；展开折叠内容后，也不能把同一主值重新复制成 raw key/value 行。
- light/dark 分别使用 macOS 系统白/黑；品牌、页标题与主数值保持 Dashis 原有 system serif，正文和控件保持 system sans，卡片使用低对比边框与克制阴影。
- 用 Debug `--visual-qa` 验证合成 Codex detail 时，不应发生账户文件/credential 读取或自动网络检查；Release 不应启用该 fixture。

### Codex

- 未点击前不读取 auth；未登录或 auth 文件不安全时只显示净化错误。
- `Check desktop usage` 优先显示响应实际返回的 Codex credits；有窗口才显示对应实际 duration，无窗口时不得出现推断出的 5-hour/weekly 值。
- available reset credits 单独显示；其中一个 endpoint 失败时另一结果仍保留并显示 partial failure。
- 只有服务端明确返回 `unlimited=true` 时当前账户才显示 `Unlimited`；该状态不能推广到其它账户或计划。
- Workspace ID + `codex.enterprise.analytics.read` key 能触发 Enterprise Analytics；key 不跨重启存在，Clear 后输入与 snapshot 清空。
- Personal 产生真实结果、失败或风险状态后标注 `Experimental`；中性未检查空态不额外显示来源。Enterprise 组织 usage 不显示为个人 remaining。

### Claude

- `Preview connect` 只验证 helper并生成 settings 变更预览；Apply 前 helper 目标路径和 `~/.claude/settings.json` 都不应变化。
- Apply 后，运行一次会返回 rate limits 的 Claude Code 响应，再点 `Reload snapshot`；出现 5-hour/7-day 数据与 `Official · Local`。
- 没有新响应时旧数据按 15 分钟 stale、24 小时 expired，不得因无关 statusLine 事件重新变 fresh。
- 原先已有 statusLine 时仍有相同输出/错误/退出状态。
- `Clear loaded data` 只删除 snapshot，bridge 仍连接；`Preview disconnect` + Apply 恢复原 statusLine 并删除 snapshot。

### Google AI

- Consumer mode 只打开 Gemini 官方页面或接受 manual reading；不自动读取个人 subscription 余额。Antigravity 余额由用户在 CLI 输入 `/credits` 人工核对。
- Project mode 要求 Desktop OAuth client ID 与手工输入的 project ID/number；可选 exact quota IDs 支持逗号/空白分隔，留空最多自动选择 24 个 definition。默认浏览器授权后只在当前 App session 保持连接。
- 缺少 `cloudquotas.quotas.get` 或 `monitoring.timeSeries.list` 时显示净化权限错误，不尝试扩大 scope。
- 成功时显示 `Official · Estimated`、project scope、quota windows 和约 150 秒延迟警告；minute/hour 历史窗在摘要明确标为 historical，detail 的对应 window/warning 给出 exact as-of，不能像 live balance，也不能在同屏多处重复同一说明。
- Clear 取消 Google listener/请求、清 token/client/project/quota-ID/manual fields 和 snapshot，不应取消正在进行的 OpenRouter 独立 flow。

### OpenRouter

- 默认 OAuth mode 在系统默认浏览器打开 OpenRouter，随机 localhost callback 授权后显示 `/api/v1/key` limit/usage/remaining。
- 取消/拒绝/超时、key 过期或 HTTP 401/403 时显示净化错误并要求重新连接。
- Clear 取消本地 listener并清 session key/snapshot；若浏览器端可能已创建 key，去 OpenRouter 官方账户页面 revoke。
- Management mode 只有用户显式提供 management key 后才查询 credits/activity/meta/query 与可选 generation；key 不持久化。
- negative remaining 如实显示；reasoning 只显示 breakdown；rate metric 不求和；analytics truncated 时自动缩窗重试一次并显示实际口径。
- 任一子请求失败时，其它成功结果仍显示，并列出 partial failure。

## 安全回归检查

- 测试和日志扫描不出现 `Bearer` 后的真实值、API key、OAuth code/state/verifier、account/workspace 私有标识或完整 JSON body。
- 合成 fixture 不从真实响应复制；使用明确虚构的 ID、数值和日期。
- Clear、mode switch、OAuth 取消和 App 退出后，本地 session credential 不可再次使用。
- Claude snapshot 不包含 cwd、session、transcript、repo、email、model、cost 或原始 stdin。
- Google consumer 流程不接触 Cookie/browser profile/Keychain/TUI；Codex/Claude 自动测试不接触用户 home 下真实文件。

## 常见验证故障

### `--verify` 被系统策略拒绝

查看最近系统日志：

```sh
/usr/bin/log show --style compact --last 2m --predicate 'eventMessage CONTAINS[c] "Dashis" OR eventMessage CONTAINS[c] "com.Vita0818.DashisMac" OR eventMessage CONTAINS[c] "AppleSystemPolicy" OR eventMessage CONTAINS[c] "AMFI"'
```

若出现 AppleSystemPolicy/AMFI 拒绝，确认脚本仍执行生成 bundle 的 provenance/quarantine xattr 准备，并使用 `ENABLE_DEBUG_DYLIB=NO`。

### Xcode logging timeout

scheme 的 Run action 已设置 `IDEPreferLogStreaming=YES`。单独的 logging initialization timeout 不一定表示 App 崩溃，应同时检查进程是否运行和系统 crash/AMFI 日志。

### Provider 真实数据缺失

真实 provider 验收只由用户在 UI 显式授权或输入 session credential 后执行；自动测试不会证明账号权限或服务端当前契约。排障时只记录 HTTP 状态类别和净化错误，不复制真实 key、账号 ID 或 response body。

## 文档任务验证

只改文档时至少运行：

```sh
git diff --check
git status --short -- .
```

若影响启动、构建、Run action、UI 流程、provider 接入、凭据、endpoint allowlist、验证或排障，必须同步更新 `docs/USER_TUTORIAL.md`。未运行构建/测试时，最终报告必须明确写“未运行构建/测试”。
