# Dia Simplified Chinese Patch

An unofficial Simplified Chinese localization patch for Dia on Apple Silicon
Macs. `v0.1.0-rc.2` is a pre-release; full WebUI coverage is verified only for
Dia `1.41.1` (Build `84131`) on macOS 14+. Core mode has also been tested on
Dia `1.44.1` (Build `85212`).

Download the macOS arm64 ZIP from GitHub Releases, verify its SHA-256 file,
quit Dia, then double-click `dia-zh.command`. The stable commands are `apply`,
`audit`, `status`, and `restore`.

The installer automatically selects `full`, `core`, or `incompatible`
coverage. Unknown but structurally compatible official builds use the safe
core mode and never receive old WebUI replacements. Set `DIA_ZH_MODE=core` to
skip WebUI patching on a known build.

The patch preserves Dia's automatic updater. After an official update, stale
patch state is superseded and an older backup will never overwrite the newer
build.

This repository contains patch source, translations, tests, and hash
manifests only. It does not distribute Dia, official JS/HTML, user data,
backups, reports, or official binaries. The arm64 menu library is built by
GitHub Actions for Release archives.

See the [Chinese README](README.md) for installation, Code 6 troubleshooting,
signing details, recovery, and development instructions.
