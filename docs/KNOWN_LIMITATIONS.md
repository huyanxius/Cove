# Preview limitations

- macOS 14+ is required. The downloadable preview targets Apple Silicon; Intel builds have not been validated. The minimum macOS version is declared as 14; the local release smoke test runs on macOS 26.
- The interface is primarily Chinese. English localization is pending.
- The app is ad-hoc signed, not notarized. Automatic updates and Homebrew distribution are pending.
- Install and authenticate the desired CLI in Terminal first. Cove uses its existing access, configuration, and model service.
- With codex-cli 0.163.0-alpha.10.2, a new native Codex conversation was not found in Cove after closing it. Native chat, tool reading and usage updates worked. Session recovery is under investigation in [#5](https://github.com/huyanxius/Cove/issues/5).
- Claude and Codex have structured conversation adapters. CLI-only interactive panels remain available in terminal modes. Unsupported Codex server requests are reported as unsupported.
- Antigravity (`agy`) is experimental. In conversation mode it has no approvals or interruption, and resuming does not display earlier messages.
- Removing a Codex session moves its rollout file to Trash; its CLI index can retain a stale entry.
- Usage availability differs between CLIs and modes. Missing data does not mean zero usage. API-rate cost estimates do not represent subscription charges.
- Protocol logs may contain prompts and tool output. Inspect them before sharing. Claude transcript backups can be turned off in Settings.

Report reproducible failures with the app, macOS, and CLI versions, interface mode, and exact steps.
