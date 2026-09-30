# Cove 交接

上一个会话（2026-09-28 至 09-30）上下文长到七十多万 token，每轮成本翻倍，所以换新会话接着做。先读 `AGENTS.md`、`docs/ROADMAP.md`、`docs/DESIGN.md`，再读这份。

## 现在在哪

- 分支 `feat/m0-shell`，已推送；PR [#2](https://github.com/huyanxius/Cove/pull/2) 开着，关联 [#1](https://github.com/huyanxius/Cove/issues/1)。PR 描述里「界面实机验收」一项如实写着未完成。
- `scripts/test.sh` 全绿（165 个）。
- 用户正在用的 Cove 从 `build/Cove.app` 启动；开发版打包在 `build/CoveDev.app`（bundle id `io.github.huyanxius.cove.dev`，偏好和正式版分开）。不要跑 `scripts/bundle.sh`：它会先删掉正在运行的 `build/Cove.app`。

## 已经有的东西（代码位置）

- 四档界面（设置 → 界面）：原生 CLI / CLI + Cove 输入框 / Cove 输入框替代 CLI 输入框 / Cove 对话界面。`CoveCore/Launch/InterfaceMode.swift`。
- Cove 对话界面：三家各一套结构化协议，统一翻成 `StreamEvent`。`CoveCore/Chat/ChatProtocols.swift`（claude stream-json、`codex app-server` JSON-RPC、agy stream-json），进程桥 `Cove/Model/ChatBridge.swift`，视图 `Cove/Views/ChatView.swift`、`MarkdownView.swift`。
- 会话控制（模型 / 思考强度 / 权限档位）由各协议提供：claude 发控制请求即时生效，codex 在下一次 `turn/start` 带覆盖，agy 只能用启动参数所以改了就在这一轮结束后按原会话重开。`CoveCore/Chat/ChatControls.swift`。
- 侧栏：CLI 筛选、置顶、归档、重命名、未读点、删除到废纸篓、按项目 / 按时间、小螃蟹敲键盘表示在干活。规则在 `CoveCore/Sessions/SessionOrganizer.swift`，只记在 Cove 的偏好里，不改 CLI 记录。
- 检查器 Git 区（`Cove/Views/GitSection.swift`）、diff 行内评论、工作树会话（`claude -w`）、会话备份（`CoveCore/Sessions/TranscriptArchive.swift`，APFS 克隆）、系统通知、复制原文、附件。
- 协议原始日志：`~/Library/Application Support/Cove/logs/<cli>-<会话ID>.log`，每一次中断都记来源。协议问题先查这里。

## 还没验证的（按优先级）

1. 侧栏新功能整体没亲眼看过：筛选条、置顶 / 归档区、悬停按钮、右键菜单、删除确认、螃蟹 `typing` 动画在 20×17 的格子里是否清楚。
2. codex、agy 的 Cove 对话界面没实机跑过完整一轮；agy 冷启动约 30 秒，改设置后的重开流程没走过。
3. claude 中途改思考强度用的是 `apply_flag_settings {effortLevel}`，协议接受但只回空应答，没确认下一轮真的生效。不生效就改成按原会话 `--effort` 重开。
4. 防误中断（Esc 连按两次、停止按钮单独放、等批准时压住新消息）刚上，没实机试。
5. 那次「被报告为用户拒绝」的中断，来源没查到（当时还没有日志）：Esc 或停止按钮误触的可能最大。

## 已知限制

- agy print 模式没有审批和打断；恢复的 agy 会话不显示历史。
- codex 发来 Cove 不支持的服务端请求（向用户提问、MCP 表单等）会被明确回绝并在对话里提示。
- 删除 codex 会话只挪走 rollout 文件，codex 自己的 `state_N.sqlite` 里那一行还在；`codex resume` 列表里可能留空壳。

## 下一步候选

- 实机验收上面 1–4，修完把 PR #2 的验收项勾上。
- Cove 空闲会话不要因界面档位 / 外观切换而重开（等下次发消息前再生效），省掉重开的等待。
- ROADMAP 里剩下的：M1 草稿持久化与输入历史、M2 hooks 回报「等你批准」给终端档位、M4 多账号与配置合并视图。

## 和用户协作的约定（这个项目里踩过的）

- 不要自己开 computer-use 操作屏幕；需要实机验收就把要看的点列给用户，或在用户明确说「你来操作」之后再动。「打开一下」只授权启动开发版。
- 用户可能正通过开发版 Cove 和你对话：换进新包可以，自己重启开发版会把会话断掉。
- 提交按功能拆成原子提交（核心 / 测试 / 界面 / 文档分开），英文 Angular 风格、三段正文、不加 AI 署名；PR 用 `git-pr` 技能。
- 界面文案、注释用中文；协议格式先用真实进程探测，再写代码和测试样本，不凭记忆。
