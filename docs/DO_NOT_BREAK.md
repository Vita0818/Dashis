# DO_NOT_BREAK

本文列出 Dashis 当前不可破坏的工程禁区。项目尚未实现前，禁止把假设写成事实。

## 工程禁区

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不创建业务源码、选择框架、安装依赖或初始化构建工具，除非用户明确要求。
- 不修改 Vitemis 其他项目，除非用户明确要求跨项目任务。
- 不在未确认真实数据源和权限模型前，把 `app.js` 的 mock 数据替换成真实 API 调用。
- 不把 Dashis 主题改成 Intatis 的香槟金、暖米色、紫蓝渐变、深蓝 slate 或其他非系统白/黑主色。
- 不把 v0.1 dashboard 改成 marketing landing page；第一屏必须保持可操作仪表盘。
- 不把 Web 或原生 macOS UI 改回装饰性品牌块、说明性 subtitle、Recent monitors、timeline 叙事面板或提示语堆叠的原型页面。
- 不放宽 `local-status-server.mjs` 的远端 endpoint allowlist；Codex 只允许两个 `chatgpt.com/backend-api/wham/*` 只读状态 endpoint，OpenRouter 只允许 `openrouter.ai/api/v1/credits`。
- 不把 Codex 状态查询改成重置、兑换、刷新登录、写入 auth 或其它有副作用的操作。
- 不让浏览器前端直接读取本机 auth 文件或直接保存 OpenRouter key；所有真实账号状态查询必须经过本地连接器。
- 不把本地连接器监听地址从 `127.0.0.1` 放宽到局域网或公网地址，除非先重新设计凭据边界。
- 不删除或降级 `Dashis.xcodeproj` 的 macOS App target `Dashis`；后续添加 iOS target 时必须保留 macOS target 和 shared scheme 可构建。
- 不在未确认 iOS 共享边界前把 `App/macOS` 源码移动成跨平台共享源码，避免提前固化错误抽象。
- 不把 macOS App 退回到纯 `WKWebView` 包装；原生 SwiftUI dashboard 是当前 macOS target 的主 UI。

## 敏感信息禁区

- 不读取、打印、摘要、复制、发送或写入 `.env`、API key、token、password、cookie、session、私钥、证书、SSH key、Keychain 内容、账号凭据或无关私人文件。
- 不把真实 API 响应、用户数据、账号标识、完整日志、完整请求体或个人隐私路径写入文档、报告或 fixture。
- v0.1 示例数据必须保持合成 mock，不得包含真实客户、账号、模型请求、响应日志或成本账单。
- `~/.codex/auth.json` 只能由本地连接器在用户显式检查 Codex 状态时读取；不得在测试、文档、日志、截图或错误信息中输出其内容。
- OpenRouter management API key 只能用于本次 `/api/status/openrouter` 请求；不得写入 localStorage、sessionStorage、日志、fixture、docs 或 Git 仓库。

## 文档禁区

- 不把未实现的 dashboard 能力写成已完成事实。
- 不把未确认的数据源、指标、权限或技术栈写成确定设计。
- 完成的持久性改动必须及时回写到相关项目文档；无需更新时必须说明原因。

## NEXT_TARGET

- `docs/NEXT_TARGET.md` 只记录一个 active target。
- 目标完成或不再有效后删除 `docs/NEXT_TARGET.md`。
- 不把 NEXT_TARGET 当作长期状态文档；长期事实应迁移到 `CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md` 或 `TESTING.md`。
