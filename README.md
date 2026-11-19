<p align="center">
  <img src="docs/img/icon.png" width="128" height="128" alt="Tether icon">
</p>

<h1 align="center">Tether</h1>

<p align="center">
  <b>Broken screen? Plug in your iPad.</b><br>
  Tether makes your iPad the Mac's screen as soon as the cable goes in.<br>
  Close the lid and keep working.
</p>

<p align="center">
  <a href="https://github.com/rzrizaldy/tether/releases/latest/download/Tether.zip"><b>Download for Mac</b></a> ·
  <a href="https://rzrizaldy.github.io/tether/">Website</a> ·
  <a href="#build-it-yourself">Build it yourself</a>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-14212a?style=flat-square">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-14212a?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-400%20lines-5ad6a0?style=flat-square">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-5ad6a0?style=flat-square">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/img/hero-dark.png">
  <img alt="A MacBook with a cracked screen connected by cable to an iPad showing the Mac's desktop" src="docs/img/hero-light.png">
</picture>

## Why

My MacBook's screen broke. The Mac still works, and I have an iPad. Sidecar can already use an iPad as a display, but you start it from Control Center, and you can't click Control Center on a screen you can't see. Then if you close the lid, the Mac goes to sleep.

Tether fixes both. Plug in the cable, and the iPad is your screen. Close the lid, and the Mac stays awake.

## How it works

| | |
|---|---|
| **The cable is the switch** | Tether watches USB. When an iPad shows up, it turns on Sidecar. If the iPad is locked, it keeps trying until you unlock it. |
| **The menu bar moves** | The iPad becomes the main display, so the Dock and new windows open there, not on the broken screen. |
| **Close the lid** | A Mac sleeps when you close the lid unless a monitor is plugged in, and macOS doesn't count an iPad as one. Tether keeps the Mac awake while the cable is in. |
| **Unplug, and it's a normal Mac** | Sleep comes back when you unplug, when you quit, and on the next launch if Tether ever crashes. It won't overheat in your bag. |

It lives in the menu bar. There's no window, no Dock icon and no settings screen, and it opens at login.

```
Your iPad · Connected
Lid can be closed
─────────────────────
Disconnect
─────────────────────
✓ Auto-connect on cable
✓ Work with lid closed
✓ iPad as main display
✓ Open at login
─────────────────────
Quit Tether        ⌘Q
```

## Install

1. **[Download Tether.zip](https://github.com/rzrizaldy/tether/releases/latest/download/Tether.zip)**, unzip it and drag **Tether** into Applications.
2. **Allow it once.** Tether isn't notarized, so macOS stops the first open. Go to System Settings › Privacy & Security, scroll down and click **Open Anyway**. Or run this in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Tether.app
   ```
3. **Turn on lid closed.** Click the iPad icon in the menu bar, choose **Work with lid closed…** and type your password. Do this once, while you can still see a screen.

### You'll need

- An iPad that supports Sidecar (iPadOS 13 or later), signed in to the same Apple ID as the Mac. The iPad has to trust the Mac the first time you plug it in.
- A keyboard when the lid is closed. One attached to the iPad works through Sidecar, or use a Bluetooth keyboard or mouse.
- macOS 13 or later. Built and tested on macOS 27.

### Good to know

- **After a restart you'll be unlocking blind.** Sidecar can't show the Mac's login screen. Open the lid and use Touch ID, or type your password without seeing it.
- **Sidecar over the cable** also charges the iPad from the Mac.
- **Tether uses Sidecar's private framework**, the same one Control Center uses. Apple doesn't publish an API for it, so a future macOS update could break it. If that happens, [open an issue](https://github.com/rzrizaldy/tether/issues).

## The password, exactly

Keeping a Mac awake with the lid shut needs `pmset disablesleep`, and that needs root. Turning on **Work with lid closed…** installs this one line at `/etc/sudoers.d/tether`, after `visudo` checks it:

```
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

That lets Tether switch that one setting on and off, with no other root access. Tether makes no network requests, collects nothing and has no account.

## Uninstall

```bash
rm -rf /Applications/Tether.app && sudo rm -f /etc/sudoers.d/tether && sudo pmset -a disablesleep 0
```

Then remove it from System Settings › General › Login Items if it's still listed.

## Build it yourself

Needs the Xcode command-line tools.

```bash
git clone https://github.com/rzrizaldy/tether.git
cd tether
./scripts/build.sh --install
```

`./scripts/build.sh` alone builds `build/Tether.app` (universal), `--install` copies it to Applications and opens it, and `--zip` writes `build/Tether.zip` and its `.sha256` for a release.

### Layout

- [`Sources/App.swift`](Sources/App.swift): the menu bar, and the logic that decides when to connect and when to keep the Mac awake.
- [`Sources/Sidecar.swift`](Sources/Sidecar.swift): connects and disconnects through `SidecarCore`.
- [`Sources/USBWatcher.swift`](Sources/USBWatcher.swift): IOKit notifications for an iPad on USB.
- [`Sources/System.swift`](Sources/System.swift): the lid-closed switch (`pmset`) and moving the main display.
- [`docs/`](docs): the website, served by GitHub Pages.
- [`scripts/`](scripts): `build.sh` and `make-icon.swift`.

## Checking a download

Each release attaches `Tether.zip.sha256`. Compare it with your copy:

```bash
shasum -a 256 ~/Downloads/Tether.zip
```

## License

[MIT](LICENSE). Made for the Mac with a cracked screen.
