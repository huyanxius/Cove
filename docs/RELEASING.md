# Releasing Cove

Releases contain an Apple Silicon app for macOS 14+, a drag-to-Applications DMG, a ZIP, and SHA-256 checksums. Current previews are ad-hoc signed, not Apple-notarized.

## Prepare

1. Use an issue and PR. Merge application prerequisites into `main` before tagging.
2. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
3. Add reviewed release notes at `docs/releases/vX.Y.Z.md`, including requirements and first-launch restrictions.
4. Verify the affected behavior, core tests, a release build, and a real first-launch session on a Mac. Do not overwrite a running Cove bundle.

## Package locally

```sh
COVE_ARCH=arm64 scripts/bundle.sh release
python3 -m unittest discover -s Tests/ReleaseTests -v
scripts/package-release.sh build/Cove.app build/distribution
```

Use a fresh distribution directory. Packaging refuses existing output, verifies the app signature and required licenses, rejects absolute dependencies outside macOS, creates and verifies a DMG, and writes `SHA256SUMS.txt`. The DMG includes an Applications shortcut and first-launch instructions.

For UI acceptance, use a separate app identifier:

```sh
COVE_BUNDLE_ID=io.github.huyanxius.cove.dev scripts/bundle.sh debug build/CoveDev.app
open build/CoveDev.app
```

## Publish

Push a version tag from a reviewed commit on `main`. The Release workflow checks that the source belongs to `main`, confirms that the tag matches the app version, runs tests, bundles, packages, creates a draft, uploads the assets, and publishes it. Manual dispatch accepts an existing tag for recovery; it does not overwrite assets that already exist.

After publishing, download the public DMG and ZIP, compare checksums, mount the DMG, check the Applications shortcut, and launch the extracted app. Confirm the README download links reach the new assets.

## Signing roadmap

Developer ID signing and Apple notarization require the owner's Apple Developer identity and credentials. Keep those in an appropriate secret store, never in the repository. Sparkle updates and a Homebrew cask remain future work.
