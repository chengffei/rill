# Rill

A macOS menu bar app that shows where your Mac's power goes, live: what the charger delivers, what the Mac draws, what flows into or out of the battery, and which apps use the most energy.

> **Status: early (0.8).** Requires macOS 26 or later on Apple silicon. Interface in English and 简体中文.

## Install

**One line in Terminal** (recommended):

```sh
curl -fsSL https://raw.githubusercontent.com/chengffei/rill/main/install.sh | bash
```

The [script](install.sh) downloads the latest release, checks its SHA-256, code signature, bundle ID and developer team, and puts Rill in Applications. Downloads made this way are not quarantined, so macOS opens Rill without a warning.

**Or download the disk image** from the [latest release](https://github.com/chengffei/rill/releases/latest), then drag Rill into Applications. Rill is signed but not notarized, so macOS blocks the first launch: open it, close the warning, then click **Open Anyway** in *System Settings › Privacy & Security*.

If the battery icon does not appear, your menu bar is full or a menu bar manager has hidden it.

## What it shows

- **Menu bar**: battery level, charging state and, optionally, live watts (charger input when plugged in, battery discharge otherwise).
- **Panel** (click the icon): an energy flow diagram from charger and battery to the Mac, a 10-minute power chart, charger and battery readings, and apps using significant energy.
- **Window** (Open Dashboard): four pages.
  - *Overview*: charge, energy flow, energy-hungry apps, today's usage.
  - *Apps*: a sortable table of energy, CPU and memory per app or per process. Quit or force quit an app, end its busiest process, or spot apps that are not responding.
  - *History*: power, charge and temperature over 1 hour to 7 days.
  - *Battery & Charger*: health, cycle count, capacity, charger rating and negotiated voltage.

Power is read from the SMC every 2 seconds; charger details and capacity come from the AppleSmartBattery registry. Per-app energy comes from `proc_pid_rusage`, grouped by responsible app the way Activity Monitor does. No special permissions are needed.

History is kept for 30 days in `~/Library/Application Support/Rill/history`. Rill goes online only when you choose **Check for Updates…**.

## Feedback

Choose **Report an Issue…** in Rill's menu. It opens a new GitHub issue with your Rill version, macOS version and Mac model filled in. Or [open one here](https://github.com/chengffei/rill/issues/new).

## Building

```sh
scripts/bundle.sh --install     # builds build/Rill.app, installs it in /Applications and launches it
swift test                      # needs Xcode's toolchain: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scripts/make-release.sh         # dmg, zip and checksums in dist/
```

## License

Rill is licensed under the [GPL-3.0](LICENSE). Contributions require agreeing to the [CLA](CLA.md), which a bot asks for on your first pull request.
