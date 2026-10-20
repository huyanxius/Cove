# Cove · Agent 协作约定

## 这是什么

macOS 原生的 Claude Code CLI 外壳。终端里跑的是原版 `claude`，外壳只补会话管理、原生输入、状态与 diff。边界和路线见 `docs/ROADMAP.md`，视觉语言见 `docs/DESIGN.md`，动 UI 前先读后者。

## 结构

- `Sources/CoveCore`：纯逻辑，不 import AppKit/SwiftUI。JSONL 解析、状态推断、任务还原、改动汇总、输入路由、命令拼装、diff 解析都在这里，全部要有测试。
- `Sources/Cove`：App 层。SwiftUI 负责布局，SwiftTerm 与 NSTextView 通过 Representable 接入。业务判断不写在 View 里，下沉到 CoveCore。
- 依赖方向只能是 `Cove → CoveCore`，反过来即违规。

## 构建与验证

```bash
swift build                 # 编译
scripts/test.sh             # 单测（CLT 环境需要补 Testing.framework 路径，脚本已处理）
scripts/bundle.sh && open build/Cove.app   # 打包成 .app 实机看
```

UI 改动必须打包运行、截图确认后再交付。

## 流程

- 不直接提交 main：issue → 分支 → PR。
- commit 用 Angular 风格，不加 AI 署名尾巴。
- 不修改用户的 `~/.claude/settings.json`；需要注入配置只走 `claude --settings`。
