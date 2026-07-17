# Dashis 项目常驻上下文

本文件继承 `/Users/vita/Vitemis/AGENTS.md` 中的 Vitemis 通用 Agent 规则。若本文件与通用规则冲突，在不违反系统和用户指令的前提下，以更具体、更严格的项目规则为准。

Dashis 当前是独立 Git 仓库，远程 `origin` 指向 `https://github.com/Vita0818/Dashis.git`。

执行任何代码修改、配置修改、构建脚本修改或测试源码修改之前，必须先按顺序阅读并核对：

0. `/Users/vita/Vitemis/AGENTS.md`
1. `docs/CURRENT_STATE.md`
2. `docs/PROJECT_MAP.md`
3. `docs/ARCHITECTURE.md`
4. `docs/DO_NOT_BREAK.md`
5. `docs/TESTING.md`
6. `docs/NEXT_TARGET.md`（如果存在）

如果文档与源码、工程配置、测试或脚本冲突，必须以当前源码和配置为准，并在最终报告中指出冲突位置和采用源码为准的原因。

## 工作目录检查

每轮开始先在项目根目录执行：

```sh
pwd
git rev-parse --show-toplevel
git status --short -- .
```

要求：

- `pwd` 必须是 `/Users/vita/Vitemis/Dashis`。
- 当前 Git root 必须是 `/Users/vita/Vitemis/Dashis`。
- 读取状态后，先区分用户已有改动与本轮计划改动；不得覆盖、回退或清理用户已有改动。

## 修改边界

Dashis 是计划中的 AI dashboard 项目。当前尚未确认技术栈、入口文件、构建方式、数据源或部署方式。

在只要求项目自查、规范迁移或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要创建业务源码、安装依赖、选择框架、初始化构建工具或改动 Vitemis 其他项目。

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不读取、打印、摘要或写入 `.env`、API key、token、cookie、session、私钥、证书、账号凭据或无关私人文件。
- 不把真实密钥、token、账号密码、完整 API 响应、完整用户数据样本或个人隐私路径写入文档、报告、fixture 或示例配置。
- 不引入新依赖、不创建构建脚本、不生成项目模板，除非用户明确要求。

## 项目理解要求

修改前至少确认：

- Dashis 当前文件结构和是否已有源码入口。
- 目标 dashboard 的用户、数据源、指标、权限和展示范围是否已被用户明确说明。
- 是否需要连接 OpenAI、内部服务、本地数据、第三方 API 或数据库；涉及凭据时必须先要求安全替代方案。
- 是否已有 `docs/NEXT_TARGET.md`，如果存在必须读取并判断目标是否仍然有效。

不确定的模块必须标注 `UNKNOWN` 或 `需要后续确认`，不要编造。

## 文档索引

- `docs/PROJECT_MAP.md`：目录、入口、配置、生成物和未知项地图。
- `docs/ARCHITECTURE.md`：当前架构事实、计划中的 dashboard 分层和未确认边界。
- `docs/CURRENT_STATE.md`：当前真实状态、已有能力、风险、工作区改动。
- `docs/TESTING.md`：环境、构建、测试、lint/format 与手动验证方式。
- `docs/DO_NOT_BREAK.md`：工程禁区、数据、权限、凭据和回归要求。
- `docs/USER_TUTORIAL.md`：中文用户教程，记录启动、界面、provider 检查、凭据安全、验收和排障方式。
- `docs/NEXT_TARGET.md`：临时下一目标记录；目标完成或不再有效后删除。

## 完成标准

完成任务前至少做到：

- 说明本轮实际阅读/检查过哪些源码、配置或测试。
- 只修改任务范围内文件。
- 保留用户已有改动。
- 运行与任务相称的检查；文档任务至少运行 `git diff --check` 与 `git status --short`。
- 将本轮已完成的持久性改动及时回写到相关项目文档；若无需更新文档，最终报告说明原因。
- 任何影响启动/构建、Run action、用户界面流程、provider 接入、凭据处理、endpoint allowlist、验证方式或排障方式的改动，必须同步更新 `docs/USER_TUTORIAL.md`；若无需更新教程，最终报告说明原因。
- 如未运行构建或测试，最终报告必须明确写“未运行构建/测试”。

## 最终报告格式

最终报告建议包含：

1. `MODEL_CHECK_RESULT`：当前模型名称；无法确认时写无法确认。
2. `PATH_CHECK_RESULT`：`pwd`、Git root、是否匹配预期。
3. `FILES_WRITTEN`：新增/修改文件。
4. `PROJECT_AUDIT_SUMMARY`：识别到的项目结构、主要模块和关键链路。
5. `DOCS_CONTENT_SUMMARY`：各文档内容摘要。
6. `VALIDATION_RESULT`：实际运行命令与结果。
7. `UNCERTAINTIES`：无法确认、需要人工确认的点。
8. `NEXT_RECOMMENDED_ACTION`：下一步建议；不要自动继续改业务源码。
