# Cove 路线图

Cove 的边界：**跑的永远是原版 CLI 进程，外壳不改 CLI 的行为**。外壳能做的事分三类——替用户输入（原生输入框）、替用户看（从 JSONL 衍生出状态、任务、改动、原文）、替用户管（会话、账号、归档）。凡是需要改 TUI 行为才能做成的功能，一律不做。

界面在设置里四选一：

| 档位 | 进程 | 中栏 |
| --- | --- | --- |
| 原生 CLI | TUI（伪终端） | 只有终端 |
| 原生 CLI + Cove 输入框 | TUI | 终端 + Cove 输入框，CLI 输入区照常可见 |
| Cove 输入框替代 CLI 输入框 | TUI | 终端 + Cove 输入框，CLI 输入区被遮住 |
| Cove 界面 | `claude -p` stream-json（Agent SDK 同款协议） | Cove 自己画的对话、原生权限卡片 |

前三档只差显示，就地切换；第四档换了进程，切换时用同一个会话 ID `--resume`，两种进程写的是同一份 JSONL。第四档目前只有 claude，codex / agy 选了它按第三档显示。第四档里没有 TUI 专属的面板（`/model` 选择器、`/config`），这是换来逐字输出和原生权限确认的代价。

## 数据来源

| 来源 | 拿到什么 | 何时用 |
| --- | --- | --- |
| `~/.claude/projects/<编码后的 cwd>/<sessionId>.jsonl` | 会话标题（`custom-title` > `ai-title` > 首条人类消息）、cwd、分支、工具调用、任务、费用 | M0 起 |
| `claude --session-id <uuid>` | 新会话的 ID 由 Cove 预先分配，标签页与 JSONL 一一对应 | M0 起 |
| `claude --resume <id>` | 恢复时沿用原 ID（不加 `--fork-session`） | M0 起 |
| `claude --settings <json>` | 只对 Cove 拉起的会话叠加 hooks / statusLine，不碰用户的 settings.json | M2 起 |
| `git diff` | 改动文件的实际差异 | M0 起 |
| `~/.codex/state_N.sqlite` 的 `threads` 表 | codex 的会话列表（只取 `thread_source = 'user'`），`codex resume <id>` 恢复 | M0 起 |
| `~/.gemini/antigravity-cli/conversation_summaries.db` | agy 的会话列表，`agy --conversation <id>` 恢复 | M0 起 |
| `claude -p --input-format/--output-format stream-json --permission-prompt-tool stdio` | Cove 界面的对话流、权限请求、斜杠命令列表、5h/7d 额度 | M0 起 |

## 已落地的跨里程碑能力

- **Git / GitHub**（检查器 Git 区）：分支与领先/落后、整个工作区的改动与增删行、提交全部、拉取（仅快进）/推送/发布分支；当前分支 PR 与 CI 检查（`gh pr view`），失败时一键交给 Agent 修；「让 Agent 提交 / 创建 PR」把活交给会话、按仓库约定先出草稿。顶栏「打开于」VS Code、Cursor、Zed、Xcode、终端、Finder。
- **diff 行内评论**：在 diff 的任意行写意见，一次打包发给当前会话。
- **并行会话**：⇧⌘N 在新工作树里开 claude 会话（`claude -w`，位置同官方 `<仓库>/.claude/worktrees/`）。
- **会话备份**：每 5 分钟把 JSONL 按原相对路径镜像到 `~/Library/Application Support/Cove/Transcripts`（APFS 克隆），被 `cleanupPeriodDays` 清掉的会话仍在侧栏、点开先复原。原属 M4。
- **通知**：会话做完或卡在权限确认上、你没在看它时发系统通知。原属 M2。
- **复制原文**：回复上的复制按钮、⇧⌘C，取 JSONL 原文，绕开终端复制的硬换行。原属 M3。
- **附件**：拖入或粘贴文件插入路径，截图先存成 PNG。原属 M1。

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

- 自绘界面去模拟 TUI 的专属面板（`/model` 选择器、`/config` 等）：要用这些就切回终端档位，追着 CLI 的内部界面复刻永远追不上。
- 解析终端屏幕内容推断状态：脆弱，一律改用 JSONL 与 hooks。
- 修改用户的 `~/.claude/settings.json`：Cove 的注入只经 `--settings` 作用于自己拉起的进程。
