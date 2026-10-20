# Contributing to Cove

Cove has a pure Swift logic layer (`CoveCore`) and a macOS app layer (`Cove`). Dependencies point from the app to the core. Keep parsing and business decisions in the core and add focused tests there.

Read [AGENTS.md](AGENTS.md), [the roadmap](docs/ROADMAP.md), and [the design language](docs/DESIGN.md). Open an issue for a concrete bug or proposed change, work on a branch, and link the PR to the issue.

## Local checks

```sh
scripts/test.sh --filter YourTestSuite
swift build
```

Choose checks covering the change. For UI changes, also build a separate app and check it on a Mac:

```sh
COVE_BUNDLE_ID=io.github.huyanxius.cove.dev scripts/bundle.sh debug build/CoveDev.app
open build/CoveDev.app
```

Do not overwrite a bundle hosting an active session. Reproduce protocol changes against the actual CLI; fixtures should reflect the observed protocol.

## Bug reports

Include macOS, Cove, and CLI versions; interface mode; reproduction steps; expected behavior; and actual behavior. Use a small disposable project where possible. Redact credentials and private content from logs before sharing.

For packaging changes, run `python3 -m unittest discover -s Tests/ReleaseTests -v` on macOS. See [release instructions](docs/RELEASING.md) for distribution checks.
