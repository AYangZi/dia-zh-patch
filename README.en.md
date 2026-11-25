# Dia Simplified Chinese Patch

An unofficial Simplified Chinese localization patch for Dia on Apple Silicon
Macs. `v0.1.0-rc.2` is a pre-release; full WebUI coverage is verified only for
Dia `1.41.1` (Build `84131`) on macOS 14+. Core mode has also been tested on
Dia `1.44.1` (Build `85212`).

The current source also fixes core-mode startup on Dia `1.58.2` (Build `91529`)
and adds native UI translations. These changes are not in the published rc.2 ZIP.
The signer strips restricted APNs entitlements, so official APNs push capability
is unavailable while patched. The menu library clears its own loader environment
after loading so nested helpers do not inherit an invalid relative library path.
Previously saved names such as `Imported Tabs` are user data and must be renamed
in Dia; the patch only adds a translation for the default name at creation time.

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
