# Dia Simplified Chinese Patch

[中文](README.md) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md) ·
[AI agent prompt](docs/AI_AGENT_PROMPT.md)

An unofficial Simplified Chinese localization patch for Dia on Apple Silicon
Macs. `v0.2.0-rc.1` is a pre-release; full WebUI coverage is verified for
Dia `1.41.1` (Build `84131`) and `1.53.0` (Build `88760`) on macOS 14+. Core
mode has also been tested on Dia `1.44.1` (Build `85212`). The native settings
window (Account / Tabs / Privacy / Profiles / Apps / Skills / Billing /
Shortcuts / Advanced) is localized panel by panel.

## Setting up on a new Mac (right after installing Dia)

Requirements: macOS 14+, Apple Silicon, Dia installed from the official
channel and launched at least once. The patch only rewrites the app bundle —
it never touches your account, bookmarks, passwords, tabs or history.

1. Quit Dia completely (⌘Q), then confirm:

   ```zsh
   pgrep -fl "/Applications/Dia.app/Contents/MacOS/Dia"   # no output = quit
   ```

2. Install, either from a Release archive (recommended) or from source:

   ```zsh
   # A. Release archive
   cd ~/Downloads
   curl -LO https://github.com/framecy/dia-zh-patch/releases/download/v0.2.0-rc.1/dia-zh-patch-0.2.0-rc.1-macos-arm64.zip
   curl -LO https://github.com/framecy/dia-zh-patch/releases/download/v0.2.0-rc.1/dia-zh-patch-0.2.0-rc.1-macos-arm64.zip.sha256
   shasum -a 256 -c dia-zh-patch-0.2.0-rc.1-macos-arm64.zip.sha256
   unzip dia-zh-patch-0.2.0-rc.1-macos-arm64.zip
   cd dia-zh-patch-0.2.0-rc.1-macos-arm64
   ./dia-zh.command audit
   ./dia-zh.command apply

   # B. From source (needs Xcode Command Line Tools)
   git clone https://github.com/framecy/dia-zh-patch.git
   cd dia-zh-patch
   ./scripts/build-menu.zsh     # builds lib/DiaZhMenu.dylib (arm64)
   ./dia-zh.command apply
   ```

   Double-clicking `dia-zh.command` works too; if Gatekeeper blocks it, use
   right-click → Open, or System Settings → Privacy & Security → "Open Anyway",
   or clear the quarantine flag: `xattr -d com.apple.quarantine dia-zh.command`.

3. Verify in 30 seconds: `./dia-zh.command status` reports `applied`; the menu
   bar and the ⌘, settings window are Chinese.

4. Do **not** copy a previously patched `Dia.app` or the
   `~/Library/Application Support/DiaZhPatch/` state folder to a new machine —
   install the official app and patch it there.

5. After an official Dia update, simply run `./dia-zh.command apply` again.

The stable commands are `apply`, `audit`, `status`, and `restore`.

## Re-signing and sign-in state (important)

The patch re-signs Dia ad-hoc. In some cases Dia then fails to recognise the
credentials it stored locally, and shows its "What's your email?" onboarding on
next launch. This is not data loss: history, bookmarks and the previous session
tabs stay in `~/Library/Application Support/Dia`. Sign in again with the same
email and the spaces come back; a Dia Recovery Kit export also works.

Prevention: quit Dia completely (⌘Q) before running `apply` or `restore`, check
that you are still signed in after patching, and keep a copy of
`~/Library/Application Support/Dia` (or a Time Machine snapshot) when the data
matters.

## Coverage and limits

The installer automatically selects `full`, `core`, or `incompatible`
coverage. Unknown but structurally compatible official builds use the safe
core mode and never receive old WebUI replacements. New builds are derived
from the unified catalog with `scripts/derive-webui-manifest.mjs`, then
reviewed and validated against the official app before being added to
`manifests/index.json`. Set `DIA_ZH_MODE=core` to
skip WebUI patching on a known build.

The patch preserves Dia's automatic updater. After an official update, stale
patch state is superseded and an older backup will never overwrite the newer
build.

Two settings titles (`Profiles`, `Advanced`) are verbatim literals and do not
read from the string table; `Chat events` and `Daily report` are not present in
the official bundle at all.

## One-line prompt for AI agents

```
On macOS, localize a freshly installed Dia browser into Simplified Chinese: clone https://github.com/framecy/dia-zh-patch, run ./scripts/build-menu.zsh (needs Xcode Command Line Tools) then ./dia-zh.command apply, verify with ./dia-zh.command status that the patch state is applied and that the menu bar and the ⌘, settings window are Chinese; if the coverage level is core instead of full, the current Dia build is not verified yet — generate its manifest with node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version <version> --build <build> --write, register it in manifests/index.json, run ./tests/run-tests.zsh until green, then apply again; on any failure or "Code 6" error, run ./dia-zh.command restore and report honestly instead of forcing it through.
```

## Repository contents

This repository contains patch source, translations, tests, and hash
manifests only. It does not distribute Dia, official JS/HTML, user data,
backups, reports, or official binaries. The arm64 menu library is built by
GitHub Actions for Release archives.

See the [Chinese README](README.md) for the full installation guide, Code 6
troubleshooting, signing details, recovery, and development instructions.
