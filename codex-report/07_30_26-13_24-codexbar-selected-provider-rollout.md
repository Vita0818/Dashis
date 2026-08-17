# CodexBar 34 Provider Rollout 与前台目录

> **历史状态，已被当前实现取代（2026-07-30）：** 本文记录的是 catalog-only 阶段，不再代表当前源码。当前实现已经升级到 wire v4，并把其余 30 个 provider 的 41 条 live explicit route 接入 Store、XPC Worker 与前台 `Check usage`；以 `docs/CURRENT_STATE.md`、`docs/ARCHITECTURE.md` 与源码为准。

## 结论

用户选定的 34 个 provider 已写入 App 与 XPC Worker 共用的 Foundation-only staging catalog。当前 pinned CodexBar `v0.45.2` / commit `91560ca98e776b96fdf910d4a0423c2f0c07a3b9` 共对应：

- 34 个 selected provider；
- 52 条 exact upstream strategy；
- 50 条可用显式 source 表达的 staging binding；
- 3 条只能由上游 `.auto` planner 进入的 strategy；
- 0 条 Worker live authorization。

后台 staging 与前台 reviewed catalog 现在使用同一组 34-provider identity：Sidebar、Dashboard 和只读详情均已开放。Codex、Claude、Gemini、OpenRouter 继续使用现有 native 流程，其余 30 个 provider 只展示已核对的采集方式，不提供 live 采集动作。Worker authorization 仍为 0，所以这不是启用 CodexBar 采集。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Dashis`
- Git root：`/Users/vita/Vitemis/Dashis`
- 与项目要求一致。

## 统一接线状态

`CollectorRolloutCatalog` 是唯一 staging 事实源。App 和 Worker 都只通过 `DashisCollectorContract` 读取它；App 不 import CodexBar Core。wire v3 handshake 会核对 catalog revision 与 34/52/50 数量，App 还会确认 50 条 binding 的 provider/source 都存在于 Worker 返回的 pinned 63-provider Core catalog。

每条 binding 仍带以下 release gate：

1. exact phase-by-phase effect manifest；
2. HTTP/Credential/LocalState/Keychain/Browser/Subprocess host broker；
3. operation-scoped Worker 与进程树 hard termination；
4. Developer ID、Hardened Runtime、notarization 与同身份签名。

Worker production authorization registry 仍为空，所以 `liveRouteCount = 0`，collect 在 strategy resolver 之前 default-deny。

## 前台投影

- `DashisProviderCatalog` 直接按 `CollectorRolloutCatalog.selectedProviderIDs` 投影固定顺序，不读取 Worker 的 63-provider 动态 catalog。
- UI navigation ID 与 collector ID 分离；`gemini` 显式映射到现有 `google` navigation/snapshot ID，因此仍是 34 项，不会重复成 35 项。
- Codex、Claude、Gemini、OpenRouter 标记为 `.native`，保留既有 action、credential 生命周期、endpoint policy 与 snapshot projection。
- 其余 30 项标记为 `.catalogOnly`，ID 稳定、可从 Sidebar/Dashboard 进入详情，但 `actionTitle = nil`，Store dispatcher 在执行前明确拒绝。
- Dashboard 只以低权重文字显示 explicit binding 对应的 API/OAuth/Web/CLI/Local strategy kind；不显示“已连接”、指标数量、假余额、假窗口或采集按钮。
- catalog-only detail 只显示 `Data sources` 与“采集尚未启用”说明。`opencodego.local`、`kimi.cli`、`mimo.local` 没有 explicit binding，因此不会被前台伪装为 prepared source。
- 启动 App、滚动目录或进入 catalog-only detail 不触发 XPC、HOME、Keychain、浏览器、CLI 或 provider 网络。

## Provider / Strategy Matrix

| Provider | Core ID | Exact strategy（kind） | Explicit source |
| --- | --- | --- | --- |
| Codex | `codex` | `codex.cli` (`cli`); `codex.oauth` (`oauth`); `codex.web.dashboard` (`webDashboard`) | `cli`; `oauth`; `web` |
| OpenAI | `openai` | `openai.api.balance` (`apiToken`) | `api` |
| Azure OpenAI | `azureopenai` | `azureopenai.api` (`apiToken`) | `api` |
| Claude | `claude` | `claude.admin-api` (`apiToken`); `claude.oauth` (`oauth`); `claude.web` (`web`); `claude.cli` (`cli`) | `api`; `oauth`; `web`; `cli` |
| ClinePass | `clinepass` | `clinepass.api` (`apiToken`) | `api` |
| Cursor | `cursor` | `cursor.web` (`web`) | `cli` 与 `web` 都解析到同一 Web strategy |
| OpenCode | `opencode` | `opencode.web` (`web`) | `web` |
| OpenCode Go | `opencodego` | `opencodego.local` (`localProbe`); `opencodego.web` (`web`) | local 仅 `.auto`；Web 为 `web` |
| Alibaba | `alibaba` | `alibaba-coding-plan.web` (`web`); `alibaba-coding-plan.api` (`apiToken`) | `web`; `api` |
| Alibaba Token Plan | `alibabatokenplan` | `alibaba-token-plan.web` (`web`) | `web` |
| Gemini | `gemini` | `gemini.api` (`apiToken`) | `api` |
| Antigravity | `antigravity` | `antigravity.app-local` (`localProbe`); `antigravity.cli-https` (`cli`); `antigravity.ide-local` (`localProbe`); `antigravity.oauth` (`oauth`) | 前三条为 `cli`；OAuth 为 `oauth` |
| Copilot | `copilot` | `copilot.api` (`apiToken`) | `api` |
| z.ai | `zai` | `zai.api` (`apiToken`) | `api` |
| MiniMax | `minimax` | `minimax.api` (`apiToken`); `minimax.web` (`web`) | `api`; `web` |
| Kimi | `kimi` | `kimi.api` (`apiToken`); `kimi.cli` (`oauth`); `kimi.web` (`web`) | API 为 `api`；CLI 仅 `.auto`；Web 为 `web` |
| Vertex AI | `vertexai` | `vertexai.oauth` (`oauth`) | `oauth` |
| Moonshot / Kimi API | `moonshot` | `moonshot.api` (`apiToken`) | `api` |
| Ollama | `ollama` | `ollama.web` (`web`); `ollama.api` (`apiToken`) | `web`; `api` |
| OpenRouter | `openrouter` | `openrouter.api` (`apiToken`) | `api` |
| Perplexity | `perplexity` | `perplexity.web` (`web`) | `web` |
| Xiaomi MiMo | `mimo` | `mimo.web` (`web`); `mimo.local` (`localProbe`) | Web 为 `web`；local 仅 `.auto` |
| Doubao | `doubao` | `doubao.cli` (`cli`); `doubao.api` (`apiToken`) | `cli`; `api` |
| Sakana AI | `sakana` | `sakana.web` (`web`) | `web` |
| Mistral | `mistral` | `mistral.web` (`web`) | `web` |
| DeepSeek | `deepseek` | `deepseek.api` (`apiToken`); `deepseek.web` (`web`) | `api`; `web` |
| Venice | `venice` | `venice.api` (`apiToken`) | `api` |
| Command Code | `commandcode` | `commandcode.web` (`web`) | `web` |
| Qoder | `qoder` | `qoder.web` (`web`) | `web` |
| StepFun | `stepfun` | `stepfun.web` (`web`) | `web` |
| AWS Bedrock | `bedrock` | `bedrock.api` (`apiToken`) | `api` |
| Grok | `grok` | `grok.cli` (`cli`); `grok.web` (`web`) | `cli`; `web` |
| LongCat | `longcat` | `longcat.web` (`web`) | `web` |
| ZenMux | `zenmux` | `zenmux.api` (`apiToken`) | `api` |

## 明确不可伪造的三条路由

- `opencodego.local`
- `kimi.cli`
- `mimo.local`

它们存在于 pinned Core，但没有显式 source 能精确选择。Dashis release wire 禁止 `.auto`，因此 catalog 只记录 strategy，不生成 binding。正确修复是让上游拆出显式 source/entry point，而不是在 Dashis 中随意把它们标成 `.cli`、`.api` 或 `.web`。

Cursor 还有一个上游语义异常：显式 `.cli` 与 `.web` 都会解析为 `cursor.web`。catalog 忠实记录两个 source binding 和同一个 exact Web strategy，后续产品层不得把 `.cli` 宣传成真正 CLI 采集。

## 高风险策略

- `azureopenai.api` 会发送最小 chat completion 探针，可能产生费用、配额消耗和推理日志。
- `ollama.api` 会 POST 空 web-search 查询验证 key，存在使用/计费风险，而且当前返回值产品价值有限。
- `doubao.api` 把只读 AK/SK usage 查询与真实 chat-completion fallback 混在同一 strategy，必须先拆分。
- `bedrock.api` 可调用 AWS CLI profile 解析，并访问可能计费的 AWS usage/cost API。
- `bedrock.api` 还能把带 SigV4 凭据证明的请求发往自定义 endpoint，必须先由 broker 固定主机。
- `antigravity.oauth` 特殊情况下会调用远程 onboarding，并可能写回 OAuth/project 状态。
- `antigravity.app-local` / `antigravity.ide-local` 会通过 `/bin/ps` 与 `lsof` 子进程检查本地进程和端口。
- `claude.cli` 在显式 CLI 路线没有登录预检；未登录时上游交互 REPL 可启动浏览器 OAuth，并写入 credential。
- `grok.web` 虽是 Web strategy，仍会启动 `grok --version` 子进程补充版本信息。
- `deepseek.api` 在启用 optional usage 时也可能读取 Chrome Local Storage；API kind 不能被当作“只读 token + 网络”的权限证明。
- StepFun 会读取内部 Keychain cache，并可能登录、刷新和写回 token；Command Code、Grok Web、LongCat 的浏览器访问门控也会写 CodexBar 本地状态。
- Codex/Claude/Gemini/StepFun 等 OAuth 或 Web 路线可能刷新并写回 credential；浏览器路线可能读取 Cookie、Local Storage、SQLite 或触发 Keychain 提示。
- 多个 provider 支持自定义 HTTPS endpoint；在 host broker 固定 allowlist 前，必须视为 credential exfiltration 风险。

`CollectorObservedEffect` 只记录这些已观察事实，不能替代完整 effect manifest。策略 kind 也不是权限边界。

## Native 重叠决策

- Codex、Claude、Gemini/Google、OpenRouter 继续保留现有 Dashis native route。
- CodexBar strategy 进入 staging catalog，但不会覆盖 native production route。
- OpenRouter 的 CodexBar 版本在账户/单 key 口径、身份和功能上弱于现有 native adapter，继续 disabled。
- 后续只有完成 exact product/account/scope 语义、canary 对比和 release gate 的单条 route 才能切换；不允许“双跑谁先返回用谁”。

## VALIDATION_RESULT

- standalone `swift test`：33/33 通过，0 failure。
- `xcodebuild test`：100/100 通过，0 failure；除真实嵌入式 XPC 的 wire v3、34/52/50 handshake、63-provider catalog 与 production default-deny 外，还覆盖 34 项 UI 顺序/唯一性、4 native/30 catalog-only 和 catalog-only dispatcher no-op。
- `ENABLE_DEBUG_DYLIB=NO xcodebuild build`：通过；App bundle 成功嵌入 `DashisCollectorWorker.xpc`。
- `plutil -lint`：Xcode project 与 Worker `Info.plist` 均通过；`git diff --check` 通过。
- 已启动构建产物做只读界面验收：Sidebar 与 Dashboard 均显示 34 项，长名称保持单行；catalog-only 行只有低权重 source 摘要和 chevron，详情只显示 `Data sources`，未点击任何采集动作。
- 测试完整编译 63-provider pinned Core，验证 34/52/50 scope、唯一性、explicit-source 覆盖、automatic-only 阻断、潜在计费标记、wire v3 handshake mismatch 拒绝和 production default-deny。
- 所有测试为 synthetic/offline；未读取真实 HOME credential、Keychain、浏览器、provider CLI 或账户数据，未执行 provider strategy。

一次复用旧 SwiftPM module cache 的尝试因 macOS `/tmp` 与 `/private/tmp`
别名造成 PCM 重复定义而触发 Swift frontend crash；换用全新的任务专用
cache/scratch path 后 33/33 通过。该问题没有涉及源码或 provider。

## 仍未完成

- 30 个 catalog-only provider 的产品级 `ProviderProductID`、account binding、credential form 与 scope 设计；
- 逐 strategy 完整 endpoint/effect manifest；
- host broker 与 endpoint allowlist；
- selected-account identity 补强；
- hard worker/process-tree termination；
- Developer ID release 签名、公证与 canary；
- live `ProviderObservation`→snapshot/UI projection。

这些是 live enablement 的前置条件，不影响本轮只读前台目录。
