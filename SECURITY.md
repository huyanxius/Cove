# Security

Cove runs local coding-agent CLIs with your account and filesystem access. Their permission settings and configured providers still apply. Review agent requests before approving them.

Do not put access tokens, account credentials, private prompts, or unredacted protocol logs in a public issue. For a vulnerability that exposes user data or bypasses an approval boundary, use [GitHub's private vulnerability reporting](https://github.com/huyanxius/Cove/security/advisories/new).

Include the Cove version, CLI and version, interface mode, a minimal reproduction, and the observed impact. Use a disposable project where possible.

The 0.1 preview is ad-hoc signed and is not Apple-notarized. Download binaries only from this repository's Releases. The latest release is the supported starting point for reproducing reports.
