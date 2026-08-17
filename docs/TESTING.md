# TESTING

## 当前测试面

Dashis 当前有四个 Xcode target：

- `Dashis`：macOS SwiftUI App。
- `ClaudeStatusLineHelper`：产物名 `dashis-claude-statusline`，嵌入 App 的 `Contents/MacOS`。
- `DashisCollectorWorker`：产物为 `DashisCollectorWorker.xpc`，嵌入 App 的 `Contents/XPCServices`；只有它链接 `CodexBarCollector`/Core。
- `DashisTests`：由 shared scheme `Dashis` 的 Test action 运行，test host 为构建后的 Dashis App。

测试源码位于：

```text
tests/DashisTests/ProviderFoundationTests.swift
tests/DashisTests/ProviderDecoderTests.swift
tests/DashisTests/ProviderCorrectnessTests.swift
tests/DashisTests/SecurityBoundaryTests.swift
tests/DashisTests/ProviderIntegrationTests.swift
```

自动测试必须使用合成 fixture、离线运行且不读取真实账户。当前没有 Web/Node 测试入口、lint/format 工具或 iOS test target。

Collector package 另有独立 SwiftPM 测试面：

```text
Packages/DashisCodexBarCollector/Tests/CodexBarCollectorTests/
```

它验证 vendored 63-provider registry、34-provider rollout scope、52 exact strategy、50 explicit-source binding、30 个 collector provider、41 条 live explicit route、3 条 automatic-only 阻断、风险/逐次 consent、per-operation exact policy、strategy provenance、account context/result identity、fallback/cancellation、中立 DTO/artifact 映射、wire v4 bounds 与 reverse broker codec。package products 已按边界接入 App/Worker target，但这套 package tests 仍独立于 shared scheme。测试不能执行真实 provider；仍没有 Web/Node 测试入口、lint/format 工具或 iOS test target。

## 推荐的完整验证顺序

从仓库根目录执行。为了避免生成物进入仓库，示例把 DerivedData 放到系统临时目录：

自动化与 Agent 的默认验证必须保持后台、无前台窗口：使用 `xcodebuild build` 或 `xcodebuild build-for-testing`，不得默认运行 `./script/build_and_run.sh`、`/usr/bin/open`，也不得假设 macOS app-hosted `xcodebuild test` 一定不会显示窗口。只有用户明确允许前台 test host、启动或视觉验收时，才进入完整 test、build/run 或 `--visual-qa` 流程。

```sh
pwd
git rev-parse --show-toplevel
git status --short -- .
plutil -lint Dashis.xcodeproj/project.pbxproj Tools/DashisCollectorWorker/Info.plist
xcodebuild -list -project Dashis.xcodeproj
xcodebuild \
  -project Dashis.xcodeproj \
  -scheme Dashis \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/dashis-tests-derived-data \
  test
xcodebuild \
  -project Dashis.xcodeproj \
  -scheme Dashis \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/dashis-build-derived-data \
  ENABLE_DEBUG_DYLIB=NO \
  build
env \
  CLANG_MODULE_CACHE_PATH=/private/tmp/dashis-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/dashis-swiftpm-module-cache \
  swift test \
    --package-path Packages/DashisCodexBarCollector \
    --scratch-path /private/tmp/dashis-codexbar-collector-build \
    --disable-sandbox
git diff --check
git status --short -- .
```

验收标准：

- `pwd` 与 Git root 都是 `/Users/vita/Vitemis/Dashis`，且没有清理或覆盖用户已有改动。
- `plutil` 通过；`xcodebuild -list` 能发现 `Dashis`、`ClaudeStatusLineHelper`、`DashisCollectorWorker`、`DashisTests` 和 shared scheme `Dashis`。
- Test action 0 failure。测试数量会随安全回归用例增长，不把固定数量当成契约。
- Debug build 通过；`Dashis.app/Contents/MacOS/dashis-claude-statusline` 存在并可由 `Bundle.url(forAuxiliaryExecutable:)` 找到，`Dashis.app/Contents/XPCServices/DashisCollectorWorker.xpc` 存在且 bundle ID 为 `com.Vita0818.DashisMac.CollectorWorker`。
- standalone collector package 编译完整 vendored Core，catalog 与 63 个 `UsageProvider` 一致；rollout inventory 固定 34/52/50，live catalog 固定 30 个 provider/41 条 route，所有测试 0 failure；scratch path 位于临时目录。
- App target 只链接 `DashisCollectorContract`；Worker target 链接 `DashisCollectorContract` 与 `CodexBarCollector`。App source/Store/UI 不 import Core，watchdog 不嵌入；Core 只随 XPC Worker 进入 App bundle。
- `ProviderIntegrationTests` 的真实 XPC 往返能完成 wire v4 handshake，核对 rollout revision/34/52/50、41 条 live route、live revision 与 manifest-set digest，并返回 63-provider catalog；未知 route 必须 default-deny。合成 live route 测试只能使用 synthetic environment/outcome，不得调用真实 provider。
- 用户明确要求前台运行验收时，`--verify` 才用于通过 LaunchServices 启动 App 并确认 `Dashis` 进程保持运行；它不是自动化默认步骤。
- `git diff --check` 无空白错误；最终状态只包含任务范围内预期变更和明确保留的用户已有改动。

## 本地 build/run

本节命令会打开可见的 Dashis 窗口，只在用户明确要求前台启动或交互验收时使用。后台构建/自动化验证继续使用上一节的 `xcodebuild`，不调用本节脚本。

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

完成 Debug build 后，只有用户明确要求视觉验收时，才用 launch argument 打开合成的 Codex detail：

```sh
/usr/bin/open -n \
    /private/tmp/dashis-build-derived-data/Build/Products/Debug/Dashis.app \
  --args --visual-qa
```

`--visual-qa` 只在 Debug 生效：它注入合成 quota、credit、reset-credit 与 warning，并自动选择 Codex route，便于验证单张 provider 主卡、卡内双主指标 pane、进度、折叠层级和 light/dark 截图。fixture 初始化不读取账户文件、credential、真实 provider response，也不自动发起网络请求；Release 不启用。它只证明视觉布局，不证明 decoder、endpoint 或真实账户数据正确。

## 自动测试覆盖要求

### CodexBar backend wiring 与 collector

- App/Worker wire v4 必须 round-trip 版本化 request/reply，拒绝 `.auto` source、非法 budget、超 256 KiB request 与超 2 MiB response。
- Worker handshake 必须报告 contract/upstream pin、rollout revision、34/52/50 staging 数量、63-provider Core catalog、`liveRouteCount = 41`、live revision 与 manifest-set digest；未知或被篡改 route collect 不得产生 attempt、usage、credits、artifact 或真实 resolver/probe。
- rollout/live 测试必须确认 provider/strategy/binding/route identity 唯一、source 从不为 `.auto`、每个 live route 都被 pinned Core catalog 支持；live 集合恰好覆盖 30 个扩展 provider，并排除四个 native provider 的重叠策略。`opencodego.local`、`kimi.cli`、`mimo.local` 只能列入 automatic-only。
- collect wire 必须携带 exact route ID、strategy ID/kind、route-manifest SHA-256、upstream pin、live revision、broker lease 与 consent 状态；App 和 Worker 任一侧不匹配都必须在进入 collector 前拒绝。该 digest 绑定 route 执行字段，不代表完整 effect manifest。
- reverse configuration broker codec 必须拒绝超过 64 KiB、超过 32 项、单值超过 16 KiB、非法键名或 route 未声明键。Client broker 必须绑定 connection/request/route/lease、最多解析一次，并在完成后移除值。
- 标记 `requiresConsent` 的 route 必须在 consent 缺失时由 Worker fail closed；UI/Store 测试必须证明 consent 是逐次的，不能沿用上次操作。
- Worker 必须 single-flight，重复 request ID 与并发 collect fail closed。Host supersede 同 target 时必须拒绝旧 run/generation 的迟到结果。
- `CollectorOutcomeValidator` 必须在映射前验证 schema、target/provider/source、exact strategy、attempt 顺序、selected-account verification、时间、有限数值与 payload cap；未经 validator 的 outcome 不得构造 `ProviderObservation`。
- `ProviderObservation` mapping 必须保留 raw `usedPercent > 100` 与负 remaining，engine/source trust/account evidence/strategy provenance 不能互相替代。
- 前台 catalog 必须与 selected 34-provider identity/order 一一对应，导航 ID 与 catalog ID 分别唯一；`google` 必须显式映射 `gemini`。恰好四项为 native、30 项为 collector。Settings 二级菜单始终使用完整 34 项 catalog且独立搜索只过滤该视图；Sidebar 与 Dashboard 自适应卡片网格使用由 Settings 原生 switch 决定的可见子集，默认全部开启。隐藏偏好跨 Store/重启保留，未知 ID 被忽略，关闭与恢复都不得改变完整 catalog、snapshot、配置或路由。Sidebar provider 行与 Dashboard 整卡只进入纯数据展示页；Settings 二级选择或切换显示开关均不得触发采集。只有 Settings 中显式的 `Check Usage` 才产生 exact command。
- 合成 collector 成功路径必须覆盖 `App/Store → XPC Worker → exact single-strategy policy → CollectorOutcome → ProviderObservation → ProviderSnapshot`；projection 后的 provider/source/strategy/时间、raw percentage 与 credits 语义不得丢失。
- 生产 native runtime 必须能在不经过 Store 的条件下执行合成 manual route；interaction 不匹配、selected credential UUID 不匹配或 project/workspace scope 不匹配必须在调用 native client 前拒绝。

- catalog 必须与 pinned Core 的全部 63 个 provider 一致。
- facade 的默认空 policy 必须在 strategy resolution 前拒绝；production Worker 为合成 live operation 注入的 policy 只能放行该 route 的 exact request/planning/strategy，exact-strategy/capability gate 必须在 `isAvailable` 前执行。
- 未知 provider/source/strategy 与缺失 capability fail closed；错误摘要不得回传 upstream diagnostic/body/token。
- request policy 必须精确覆盖 runtime、account scope、credits、optional usage 与 interaction；selected account resolver 缺失或 ID 不匹配时不得 resolve strategy。
- fetch 返回的 strategy ID/kind 必须与 exact-approved strategy 一致；不一致时不得发布 resolved source 或 usage。
- selected account 的 environment/settings 必须完整替换 ambient host context；identity expectation 缺少稳定 anchor 时不得 resolve strategy。fetch 后 missing/blank identity、provider mismatch、expectation mismatch 或 dashboard/usage email 冲突必须整包拒绝并停止 fallback；只有验证通过的 Codable schema v2 outcome 可标为 `.resultVerified`。
- fake strategy harness 必须覆盖 policy-denied resolver/probe、fallback attempt 顺序与 cancellation；仍不得执行真实 provider strategy。
- `usedPercent > 100` 与负 remaining 原样保留；synthetic placeholder 和 `usageKnown=false` 仍可辨认。
- Z.ai、MiniMax、DeepSeek、OpenCode Go、Cursor requests、Command Code live-only 数据与 OpenAI dashboard 必须进入 versioned artifact；usable result + diagnostic 必须仍是成功加 warning。
- Claude credential comparison 必须区分 matched、mismatch、absent、unavailable 与 notApplicable；matched 只能保留状态，不能把 transient persistent-ref hash 写入 Codable outcome。
- 只有 credit limit 而没有真实 balance provenance 时，remaining 必须保持 unknown，不能固化为 0。
- usage、credits 与 cost 时间分开保存，综合 freshness 取最早非 nil component。
- Worker 测试只能用 synthetic environment/broker values，并验证 route-key allowlist、one-use lease 和 operation isolation。Worker 启动环境必须只保留显式 runtime/test-safety allowlist；route 键只在操作期间安装到真实 process environment，供 Core 直接读取与子进程继承。测试与文档仍必须承认 HOME/本地文件、login-shell rc、浏览器、Keychain、网络与 detached subprocess 不属于完整 process sandbox。
- 测试只使用合成 snapshot、synthetic exact live route 和 default-deny。不得执行真实 provider、网络、Keychain、browser profile、HOME credential、SQLite、CLI 或 watchdog。

独立验证命令必须把 build/checkouts 放在临时目录。首次解析固定依赖可能需要网络；解析完成后的测试本身必须离线：

```sh
env \
  CLANG_MODULE_CACHE_PATH=/private/tmp/dashis-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/dashis-swiftpm-module-cache \
  swift test \
    --package-path Packages/DashisCodexBarCollector \
    --scratch-path /private/tmp/dashis-codexbar-collector-build \
    --disable-sandbox
```

### Provider foundation

- 固定 34-provider 前台 catalog、4 native/30 collector integration、41 条 method 只来自 live explicit route、`Settings` 保持稳定顶层选择且只把旧 `providers` alias 归一化为 Dashboard；覆盖 provider 显示偏好的默认全开、隐藏/恢复、跨 Store 持久化、Settings 目录不变、未知 ID 拒绝及已隐藏选择回到 Dashboard，以及四个 native provider 的 scope/source/freshness/no-data 行为。
- snapshot 到摘要与类型化详情卡片的投影；返回窗口优先、credit-only 不虚构窗口、OpenRouter 重复 balance/window 去重、negative remaining 保留。只有 percentage 或可验证 numerator/positive denominator 才生成 progress，未知 denominator 不退化为 `0%`。
- 安全 JSON 数值/布尔/日期转换；非有限值、错误类型和过大整数 fail closed。
- endpoint policy 拒绝非 HTTPS、错误端口、lookalike host、embedded credentials、fragment、trailing slash、dot segment、重复/未知 query、错误 method/content type/body。
- OpenRouter generation analytics policy 要求 `generation_id`、最多 2 个 dimensions、hour/day granularity、`group_limit: 1`、最多 31 天和最多 50 行；generation ID 作为有界、无控制字符的 opaque value 处理，不能把官方示例中的 `gen-` 当 schema 前缀；`/generation/content` 必须保持拒绝。
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

- Store 默认必须是 `Account` mode；OpenRouter 详情在未输入 management key 时提供 `Set up account` 路径，输入后才提供 `Check whole account`。切换 `Single key` 后才允许发起会创建普通 key 的 OAuth flow。
- 账户 snapshot 的 `/activity` 请求不得带 `api_key_hash`/`user_id`，analytics query 不得静默添加 filters；账户 credits/activity/analytics 继续保持 management-key scope。
- Recent-call query 必须通过 meta 选择 `generation_id`、最多一个 key/model 辅助 dimension、一个 cost/usage metric 和一个 token metric；请求固定无 filters/order_by、显式 1–30 天窗口、`group_limit: 1` 且 UI limit 为 20。
- Recent-call decoder 必须验证 generation ID、有限且非负的数值、整数 token、metadata row count/truncated、去重与冲突重复；非法行 fail closed。
- Recent-call loading/error/result 必须与账户 snapshot 分离：列表失败保留账户余额；recent-call 窗口变化必须清掉旧列表；management key 变化、mode switch 或 Clear 后旧列表和旧 snapshot 都不能恢复。测试必须用可控延迟响应覆盖 account check 期间 Clear 与 recent-call query 期间 mode switch。
- `/key` 直接 `limit_remaining` 与负值；credits 的负 `total_credits - total_usage`。
- OAuth 授权参数不包含未被官方契约定义的 state；随机 callback path + PKCE 的约束。
- activity/generation 的 `total_tokens` 优先；fallback 只用 prompt + completion，reasoning 不重复相加。
- rate/非可加总 metric 不跨 row 伪造总和。
- analytics meta-driven metric/dimension、metadata row count、`truncated` 警告与非法 schema。
- credits/activity/analytics/generation partial failure 相互隔离。
- `Clear` 或 mode switch 后，迟到响应不能恢复已清除 key/snapshot。

## 手动 UI 验收

### 全局

- Sidebar 使用系统 `List(selection:)`；列表顶部第一行始终完整可见原有 `Dashis` 品牌名，必须是 28 pt semibold Serif、原 vertical padding、`x: 7 / y: 9` 位置，并在固定 218 pt Sidebar 中保持原视觉起点。品牌不可选择且没有图标、subtitle 或背景；随后显示完整的 `Dashboard`、`Settings` 与当前开启 provider，不得像 2026-08-17 回归截图那样统一丢失 leading 字符。provider 行仍由系统控制行高、强调色与选中态，不存在泛化图标、逐行 offset 或浅蓝描边选中底。
- 主 Sidebar 不显示搜索框。Gemini 的导航 ID 继续是 `google`，但不重复出现 Google AI；provider 始终按 selected catalog 稳定顺序排列。
- 每个 Sidebar provider 行是纯文本系统导航；没有泛化 provider 图标、chevron、逐行 `Configure`、检查、连接状态或指标数。点击行只进入纯数据展示页，不应唤起 Worker、读取凭据或联网；导航返回依赖始终可见/可恢复的系统 Sidebar，而不是自制 toolbar back。
- Dashboard 按 catalog 顺序显示当前开启 provider 的唯一系统 `GroupBox` 展示卡；内容宽时双列、空间不足时单列，未检查的 collector 显示 `Not checked`。全部关闭时显示 `No Providers Shown` 系统空态并提示前往 Settings。整卡可进入对应纯数据展示页，但 Dashboard 不显示 Check、Connect 或 `Configure` 按钮，也不执行采集。不得显示 v0.1 mock telemetry、runs、WebView、网页、Node gateway、只有名称/右侧摘要的降级列表或旧统计小卡墙。
- 验收 OS 26/27 原生外壳：除受保护的 Dashis Serif 品牌、固定 218 pt 主 Sidebar 和固定 220 pt Settings 面板外，全窗口只有一个默认样式的 `NavigationSplitView`；系统 title/Sidebar/List、Settings 原生 `NSSearchField` / `.inset` List / switch / 被动 Divider、Dashboard ScrollView/LazyVGrid/GroupBox、grouped Form/Section/LabeledContent/ProgressView/Picker/Disclosure/Menu/按钮在 light/dark 下保持平台外观。不得出现第二个 navigation/split container、右上角二级 Sidebar 恢复按钮、固定页面色、自绘玻璃、serif provider 导航、逐行手工 offset/选中背景、手绘开关、手绘进度条或卡片阴影；仅 warning、failure 与更多操作保留有语义的系统 symbol。
- Dashboard 每个可见 provider 只有一张紧凑系统 `GroupBox` 展示卡；无 snapshot 时只显示 provider 名称与真实空态，有 snapshot 时复用类型化 projection，在同一外层卡内最多突出两个等权 pane。Dashboard 卡不显示额外 metadata、长 warning body 或任何设置动作。每个 provider 展示页也只有一张更完整的系统 `GroupBox` 主卡，主要 quota/balance 或 KPI 在同一卡片内最多两个 pane 中展示，并在窄宽度自动纵排。展示页不出现 Form、credential、method、consent、Check、Clear 或 Advanced。顶层 `Settings` 必须打开第二层可搜索 provider 菜单，菜单始终包含完整 34 项且每行右侧有系统 `.switch` `Toggle`；关闭后该 provider 立即从主 Sidebar 和 Dashboard 同时消失，但仍留在 Settings 并可重新打开，已有数据与设置不变，跨启动仍保持。右侧配置 Form 限制为最大 900 pt、字段最大 420 pt。collector 只显示 `Connection`、按需 `Credentials`、唯一 `Check Usage` 主操作与 `Advanced`；无字段时不显示 Access，所有常驻说明 footer 和风险卡都应不存在。Codex/Claude/Gemini/OpenRouter 也不得显示常驻解释 footer。凭据、风险与操作不得塞进展示主卡。
- Settings 二级菜单必须是唯一外层 detail 内固定 220 pt、不可折叠的面板；源码中只允许一个 `NavigationSplitView`。分别在默认 1160 × 760 和最小 960 × 640 窗口下进入 Settings、搜索、选择 `Alibaba Token Plan` / `Moonshot / Kimi API` 等长名称、切换显示开关并返回 Dashboard：`Dashis`、Dashboard、Settings 与 provider 名称的 leading edge 必须完整，主列不能横向滚偏，二级菜单必须始终存在，toolbar 不能出现二级 Sidebar 的双箭头/恢复按钮。二级边界不可拖动；长名称应尾部截断且 tooltip 完整，switch 应维持系统尺寸。关闭窗口前若停在 Settings，下一次启动应先显示 Dashboard。
- Clear 只在确有对应本地状态时出现在 ellipsis 更多操作菜单；默认页面不能同时摆放多个同权重主按钮。OpenRouter Clear 的服务端 revoke 确认、Claude disconnect 与其它已有安全语义保持不变。
- 订阅/限额型 snapshot 的前两个实际窗口必须进入 Dashboard 卡与详情主卡的第一视觉层级；真实提供 5-hour/7-day 时它们优先显示，但没有实际窗口时不得补造。余额/充值型 snapshot 在没有主窗口时优先显示真实 balance。两个主值不得再各套小卡；Dashboard 卡到此为止，主要数据之外的 quota/metric 与 metadata 只在详情主卡内默认折叠。
- 主卡只在 percentage 或 numerator/positive denominator 可验证时显示进度；limit-only、未知 denominator 与普通 KPI 不得出现伪造 `0%`。卡片必须沿用系统 `GroupBox`、`Divider` 和 `ProgressView`，不能出现自绘材质、描边、阴影或内嵌卡片墙。
- warning 与 partial failure 在同一主卡内各完整出现一次且不另套 surface；展开 More usage data / Data details 后，也不能把同一主值重新复制成 raw key/value 行。
- 用 Debug `--visual-qa` 验证合成 Codex detail 时，不应发生账户文件/credential 读取或自动网络检查；Release 不应启用该 fixture。
- 启动 App、滚动 Sidebar、打开 provider 展示页、进入/搜索 Settings、切换二级 provider 或显示开关都不应唤起 Worker、执行 CodexBar strategy、读取凭据或联网；Worker handshake 应报告 41 条 live route，但只有用户在 Settings 中点击 `Check Usage` 才创建 collect operation。
- 文档/布局验收不点击 `Check Usage`，不输入真实 credential，也不运行真实 provider。需要验证 controls 时只检查导航、Settings 搜索与显示开关、method 切换、字段显隐、`Advanced` 和 Clear 菜单的本地状态；正常页面不得常驻 method/credential/risk/lifecycle 提示。逐次确认弹窗由合成 UI/Store 路径或用户明确前台验收验证。
- 临时配置输入必须只在当前 App session 内可见；切换 method 只能提交该 route 声明的键，`Clear Session Data` 后输入、observation 和 snapshot 均消失。留空字段可能通过同一 broker 使用 App 启动环境中的 matching route key，或使用本地 provider/CLI/browser 配置；该事实保留在教程和安全文档，不要求作为常驻 UI footer。
- 高风险 route 每次点击 `Check Usage` 都必须再次出现确认；取消后不得建立 collect。确认文案应覆盖该 route 的风险摘要，不得把先前同意持久化为全局授权。

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

- 默认 `Account` mode 在 Settings → OpenRouter 提供 session-only management key 设置；输入后显示 `Check whole account`，成功后 OpenRouter 展示页主卡显示账户 credits remaining，而不是任一普通 key 的 `limit_remaining`。
- Account mode 不创建推理 key，并查询账户级 credits、无单-key过滤的聚合 activity、meta/query analytics 与可选 generation；management key 不持久化，Dashis 不调用 key 管理写接口。
- `/activity` 的行数必须标为 groups/聚合，不得显示成逐调用 logs；Analytics options 默认折叠。
- 账户检查成功后，`Recent calls · metadata only` 可按 1–30 天加载最多 20 条 analytics 行；不得显示 prompt/response，截断时必须明确警告，列表失败不能清掉余额。
- 切换 `Single key` 后才在系统默认浏览器打开 OpenRouter OAuth；随机 localhost callback 授权后显示 `/api/v1/key` limit/usage/remaining。取消/拒绝/超时、key 过期或 HTTP 401/403 时显示净化错误。
- Single-key Clear 取消本地 listener并清 session key/snapshot；若浏览器端可能已创建 key，去 OpenRouter 官方账户页面 revoke。Account Clear 只清内存中的 management key、snapshot 和 recent-call metadata。
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

### Collector Worker 缺失或握手失败

先检查构建产物是否存在：

```sh
test -x /private/tmp/dashis-build-derived-data/Build/Products/Debug/Dashis.app/Contents/XPCServices/DashisCollectorWorker.xpc/Contents/MacOS/DashisCollectorWorker
plutil -p /private/tmp/dashis-build-derived-data/Build/Products/Debug/Dashis.app/Contents/XPCServices/DashisCollectorWorker.xpc/Contents/Info.plist
```

bundle ID 应为 `com.Vita0818.DashisMac.CollectorWorker`。若 XPC test 失败，先检查 App target dependency、XPC embed phase、App/Worker 签名身份、wire version 是否为 4、live route count 是否为 41、live revision 和 manifest-set digest 是否一致；不要通过运行真实 provider、修改 route catalog 或放宽 exact authorization 来排障。

### Collector check 被拒绝

- `unknown_route`、manifest/pin/revision mismatch：确认 App 与 Worker 来自同一次构建，且没有混用旧 bundle；重新构建而不是改成 `.auto`。
- configuration broker/lease 错误：确认请求使用新的 per-operation lease，所提交键都来自当前 route 的配置字段，且没有复用已消费 connection。不要把任意环境变量加入 allowlist。
- `route_consent_required`：高风险 route 必须由用户在本次操作确认；不要在测试、启动参数或 Store 中硬编码 consent。
- strategy unavailable/本地配置缺失：只显示净化错误。字段留空时 Core 可能读取 matching local config；排障不得读取、打印或复制真实 HOME、Keychain、浏览器 session 或 CLI 凭据。
- timeout/cancel：确认 App 拒绝迟到结果，Worker 执行 cancel + `collector.shutdown()` + 2 秒 grace，并在超时后退出；process-group kill 仍不能证明所有 detached child 已终止。检查 Worker/系统日志时不得输出临时配置。

### Provider 真实数据缺失

真实 provider 验收只由用户在 UI 显式授权或输入 session credential 后执行；自动测试和本次文档验证都不运行真实 provider，也不会证明账号权限或服务端当前契约。排障时只记录 HTTP 状态类别、route/strategy ID 和净化错误，不复制真实 key、账号 ID、ambient environment 或 response body。

## 文档任务验证

只改文档时至少运行：

```sh
git diff --check
git status --short -- .
```

若影响启动、构建、Run action、UI 流程、provider 接入、凭据、endpoint allowlist、验证或排障，必须同步更新 `docs/USER_TUTORIAL.md`。未运行构建/测试时，最终报告必须明确写“未运行构建/测试”。
