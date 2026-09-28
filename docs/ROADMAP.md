# Cove 路线图

Cove 的边界只有一条：**终端里跑的永远是原版 `claude`，外壳不重写 CLI 的任何交互**。外壳能做的事分三类——替用户输入（原生输入框）、替用户看（从 JSONL 衍生出状态、任务、改动、原文）、替用户管（会话、账号、归档）。凡是需要改 TUI 行为才能做成的功能，一律不做。

## 数据来源

| 来源 | 拿到什么 | 何时用 |
| --- | --- | --- |
| `~/.claude/projects/<编码后的 cwd>/<sessionId>.jsonl` | 会话标题（`custom-title` > `ai-title` > 首条人类消息）、cwd、分支、工具调用、任务、费用 | M0 起 |
| `claude --session-id <uuid>` | 新会话的 ID 由 Cove 预先分配，标签页与 JSONL 一一对应 | M0 起 |
| `claude --resume <id>` | 恢复时沿用原 ID（不加 `--fork-session`） | M0 起 |
| `claude --settings <json>` | 只对 Cove 拉起的会话叠加 hooks / statusLine，不碰用户的 settings.json | M2 起 |
| `git diff` | 改动文件的实际差异 | M0 起 |

## 里程碑

**M0 · 外壳骨架**：一个窗口，三栏。
- 会话侧栏：按项目分组、按最近活动排序，点击即在对应 cwd 里 `--resume`；新建会话选目录。切走的会话进程在后台保留。
- 中栏：SwiftTerm 承载真 PTY；下方原生输入框，Enter 发送（bracketed paste 注入）、⇧↩/⌥↩ 换行，完整支持鼠标、选区、撤销、中文输入法。输入框为空时方向键、Esc、Enter、Tab、⇧Tab、Ctrl 组合键透传给终端。
- 状态条：这个 Agent 现在在干什么（思考中 / 在跑某个工具 + 摘要 / 等你），任务进度 n/m，本会话 +/- 行数。
- 检查器：任务清单、本会话改动过的文件，点文件看 diff。
- App 图标与视觉语言落地。

**M1 · 输入框打磨**：草稿按会话持久化；输入历史；拖入文件变 `@路径`、粘贴图片落盘后以路径注入；可见的发送队列（claude 忙时排队，空闲时注入）；Esc 防误触确认。

**M2 · 状态与通知**：通过 `--settings` 注入 Notification / Stop hooks，经本地 socket 回报；侧栏状态点区分「等你批权限」「跑完了」；系统通知；statusLine 透传链（先执行用户原命令，再取走上下文 % 与 5h/7d 额度）并常驻显示。

**M3 · 阅读与检索**：阅读侧栏按 JSONL 原生渲染回复，完整展开工具输出与表格；每条回复「复制原文」（绕开终端复制的缩进和硬折行）；全量会话本地全文索引与搜索。

**M4 · 守护与管理**：JSONL 归档，抵御 `cleanupPeriodDays` 的静默删除并提示；多账号 profile（每会话一个 `CLAUDE_CONFIG_DIR`）；settings / MCP / CLAUDE.md 生效值只读合并视图；「重启并续上」按钮对付长会话卡顿。

**M5 · 发布**：签名、公证、Sparkle 更新、Homebrew cask。

## 明确不做

- 自绘聊天气泡替代终端：那是官方 Desktop 和其他项目的路线，追不上 CLI 更新。
- 解析终端屏幕内容推断状态：脆弱，一律改用 JSONL 与 hooks。
- 修改用户的 `~/.claude/settings.json`：Cove 的注入只经 `--settings` 作用于自己拉起的进程。
