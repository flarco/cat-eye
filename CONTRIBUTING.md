# Contributing to Cat Eye

Thanks for your interest! Cat Eye is intentionally small: a single Swift file, zero dependencies beyond macOS and the `gh` CLI. Contributions that keep it that way are very welcome.

## Getting started

```bash
git clone https://github.com/flarco/cat-eye.git
cd cat-eye
./build.sh
open CatEye.app
```

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

The build signs with the first "Developer ID Application" identity in your keychain. If there is none, it uses an ad-hoc signature. With an ad-hoc signature, the Keychain asks again for the relay secrets after each rebuild. To select an identity, set `CODESIGN_IDENTITY`:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

## Guidelines

- **Keep it lean.** No external packages, no frameworks beyond AppKit, UserNotifications and Network. The app lives in `main.swift`. The repo picker is in `repo_catalog.swift` and `repo_settings.swift`. The optional live updates code is in `relay.swift` and `relay_settings.swift`, and the Cloudflare Worker is in `worker/`.
- **Security matters.** The app shells out to `gh` only via hardcoded trusted paths with an allowlisted environment, and validates all repo input. Don't weaken these.
- **Accessibility matters.** Status is never conveyed by colour alone (we use the Okabe-Ito palette plus shape/text signals). New UI should follow the same rule and stay keyboard-navigable.
- **No telemetry, no GitHub tokens.** GitHub auth goes through the `gh` CLI, and Cloudflare auth goes through wrangler. The only secrets Cat Eye keeps are the relay device token and webhook secret. They stay in the Keychain and go to `gh` and `wrangler` on stdin, never in argv.

## Submitting changes

1. Fork the repo and create a branch.
2. Make your change and verify it builds (`./build.sh`), passes `CatEye.app/Contents/MacOS/cat-eye --selftest`, and runs. For Worker changes, run `npm install && npm test` in `worker/`.
3. Update the README if behaviour or configuration changed.
4. Open a pull request with a clear description of what and why.

## Reporting bugs

Open a GitHub issue with your macOS version, `gh --version` output, and steps to reproduce. Screenshots help — but please use demo data, not your real repo names.
