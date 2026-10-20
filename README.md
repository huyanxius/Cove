<p align="center"><img src="docs/assets/banner.svg" width="100%" alt="Cove — a native macOS workspace for your coding agents"></p>

<p align="center">
  <a href="https://github.com/huyanxius/Cove/releases/latest"><img src="https://img.shields.io/github/v/release/huyanxius/Cove?style=flat-square&amp;color=2E5E8C" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-2E5E8C?style=flat-square" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-2E5E8C?style=flat-square" alt="Apple Silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-6D6A63?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/huyanxius/Cove/releases/latest/download/Cove-macOS-arm64.dmg">Download for Mac ↓</a></strong>
  &nbsp; · &nbsp; <a href="README.zh-CN.md">中文</a>
  &nbsp; · &nbsp; <a href="docs/INSTALL.md">Installation</a>
  &nbsp; · &nbsp; <a href="https://github.com/huyanxius/Cove/issues/new/choose">Feedback</a>
</p>

Cove brings **Claude Code and Codex** into a native macOS workspace. Pick up a session from the sidebar, write in a proper Mac text editor, and review changes beside the conversation. Your installed CLI still runs the agent, using its own account and configuration.

<p align="center"><img src="docs/assets/workspace.png" width="100%" alt="Cove running a real coding-agent session with the session sidebar, native conversation and inspector"></p>

## Get started

1. **Install your agent.** Install and sign in to [Claude Code](https://code.claude.com/docs/en/setup) or [Codex](https://developers.openai.com/codex/cli/) in Terminal. Confirm it can start a conversation.
2. **Install Cove.** [Download the DMG](https://github.com/huyanxius/Cove/releases/latest/download/Cove-macOS-arm64.dmg), open it, and drag **Cove.app → Applications**. A [ZIP](https://github.com/huyanxius/Cove/releases/latest/download/Cove-macOS-arm64.zip) is also available.
3. **Open a project.** Onboarding detects installed CLIs. Choose one, then press **⌘N** to select a project or **⌥⌘N** for a temporary session.

**First launch:** this preview is ad-hoc signed and has **not been notarized by Apple**. If macOS blocks it, attempt to open Cove, then use **System Settings → Privacy & Security → Open Anyway**. [Apple's instructions](https://support.apple.com/en-us/102445) · [Troubleshooting](docs/INSTALL.md).

Requires **macOS 14+ and Apple Silicon**. The interface is primarily Chinese. Cove does not bundle a CLI, model, or subscription. Automatic updates are not included yet.

## A workspace around your CLI

| | What Cove adds |
| :--- | :--- |
| **Sessions you can find** | Browse by project, search titles, pin, rename, and archive. Resume an existing session where you left off. |
| **A native composer** | Multiline editing, selection, undo, Chinese input methods, file attachments, and pasted images. |
| **Your choice of interface** | The original terminal, a terminal with Cove's composer, or a native conversation view with streaming and permission prompts. |
| **Changes beside the conversation** | Tasks, changed files, diffs, and line comments you can send back to the agent. |
| **Git within reach** | Branch and working-tree status, commit, pull, push, and PR checks through an authenticated `gh` installation. |
| **Session context** | Available model, context, token, and quota information. A small crab follows the agent's activity. |

Claude sessions also support separate Git worktrees, transcript backups, and copying the last reply from the original transcript.

### Integrations

| Agent | Terminal modes | Native conversation | Notes |
| :--- | :---: | :---: | :--- |
| **Claude Code** | Yes | Yes | Tool activity, permissions, session restore, and available usage. |
| **Codex** | Yes | Yes | App-server integration, permissions, session tokens, and available quota. Unsupported server requests are reported in the conversation. |
| **Antigravity (`agy`)** | Yes | Experimental | No approvals or interruption in conversation mode; resumed history is not displayed there. |

**Preview issue:** new Codex conversations may disappear from Cove after closing on the tested CLI version. Track [#5](https://github.com/huyanxius/Cove/issues/5).

Usage data depends on the CLI and interface mode. Missing data does not mean zero usage. API-rate cost estimates are estimates, not a subscription bill. See [known limitations](docs/KNOWN_LIMITATIONS.md).

## Keyboard shortcuts

| Shortcut | Action |
| :--- | :--- |
| ⌘N / ⌥⌘N | New project session / temporary session |
| ⇧⌘N | New Claude session in a separate Git worktree |
| ⌘K / ⌘L | Search sessions / focus composer |
| ⌘/ | Switch between CLI input and Cove input |
| ⌥⌘I | Show or hide the inspector |
| ⇧⌘C | Copy the last Claude reply from its transcript |
| ↩ / ⇧↩ | Send / new line |
| Esc twice | Interrupt a supported native conversation |

## Data and permissions

Cove reads local CLI session indexes and launches the agent through your login shell. The CLI's account, environment, tools, and configured provider still apply. Claude-specific settings are overlaid on Cove's process with `--settings`; Cove does not edit your global `~/.claude/settings.json`.

Claude transcript backups and protocol logs live under `~/Library/Application Support/Cove/`. Backups can be disabled in Settings. **Logs may include prompts and tool output**; inspect and redact them before sharing. Agent requests go to the service configured in your CLI.

## Build and contribute

Use Xcode or Apple's Command Line Tools with a **Swift 6** toolchain:

```sh
git clone https://github.com/huyanxius/Cove.git
cd Cove
scripts/bundle.sh
open build/Cove.app
```

For a separate development bundle and preferences:

```sh
COVE_BUNDLE_ID=io.github.huyanxius.cove.dev scripts/bundle.sh debug build/CoveDev.app
open build/CoveDev.app
```

Run focused tests with `scripts/test.sh --filter YourTestSuite`. The wrapper supports Command Line Tools installations. Intel source builds are unverified.

[Contributing](CONTRIBUTING.md) · [Architecture and roadmap](docs/ROADMAP.md) · [Design language](docs/DESIGN.md) · [Release process](docs/RELEASING.md) · [Security](SECURITY.md)

Cove is an independent project under the [MIT license](LICENSE). The terminal is powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), also MIT-licensed. Product names belong to their respective owners.
