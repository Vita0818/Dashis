# TESTING

## 当前状态

Dashis 当前包含：

- 无依赖静态 Web 原型。
- Node 内置 `node:test` 状态连接器测试。
- Xcode macOS App target `Dashis` 和 shared scheme `Dashis`。

## 本地运行

可直接在浏览器打开：

```sh
open index.html
```

或用本地静态服务器运行：

```sh
python3 -m http.server 8000
```

然后访问 `http://localhost:8000/`。

账户状态面板需要运行本地连接器：

```sh
node local-status-server.mjs
```

然后访问 `http://localhost:8787/`。

## 手动验证

- 页面加载后应显示 Dashis 左侧导航、title-only header、四个指标卡、图表、Runs 表格和右侧 inspector。
- Web 和原生 macOS UI 不应显示装饰性品牌图标、说明性 subtitle、Recent monitors、Task timeline 或操作提示语。
- 点击左侧 Overview / Models / Runs / Alerts，主标题和相关过滤状态应更新。
- 点击 Latency / Quality segmented control，图表折线指标应切换。
- 切换 Range 和 Model 下拉菜单，指标、图表或表格应更新。
- 点击 Runs 表格行，右侧 inspector 应展示对应 run。
- 点击 Pause monitor，按钮应切换为 Resume monitor，再点一次恢复。
- 运行 `node local-status-server.mjs` 后，点击 Accounts / Check Codex：
  - 若本机已登录 Codex Desktop，应显示 Codex plan、usage windows 和 reset credits。
  - 若未登录，应显示本地连接器返回的登录提示，不应展示 token 或 auth 文件内容。
- 在 OpenRouter status 中输入已登录账号创建的 management API key，点击 Check OpenRouter，应显示 remaining、used、total credits；点击 Clear 后输入框应清空，页面不应持久化 key。
- 系统深色模式下，页面背景应为 macOS 系统黑；浅色模式下页面背景应为 macOS 系统白。

## 自动验证

语法检查：

```sh
node --check app.js
node --check local-status-server.mjs
```

状态逻辑测试：

```sh
node --test tests/status-logic.test.mjs
```

测试不得读取真实 `~/.codex/auth.json`，不得使用真实 OpenRouter key。

Xcode 项目可发现性检查：

```sh
xcodebuild -list -project Dashis.xcodeproj
```

macOS Debug build：

```sh
xcodebuild -project Dashis.xcodeproj -scheme Dashis -configuration Debug -destination 'platform=macOS' build
```

当前 `Dashis` scheme 构建 macOS App target。macOS App 主 UI 是原生 SwiftUI dashboard；Web 原型仍可用浏览器方式单独验证。

## 文档任务验证

文档或规范任务至少运行：

```sh
git diff --check
git status --short
```

## 未来需要补充

当技术栈确定后，必须更新本文：

- 本地开发命令。
- build 命令。
- unit test 命令。
- lint/format/typecheck 命令。
- dashboard 手动验收路径。
- 数据源 mock 或 fixture 验证方式。
- iOS target 的构建、运行和模拟器验收路径。

如果未运行构建或测试，最终报告必须明确说明原因。
