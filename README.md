# Cool Tools

<img src="Assets/icon-1024.png" width="128" align="right">

A tiny SwiftUI menu bar app that replaces my Karabiner-Elements setup and adds a few extras.

| Key | Does |
| --- | --- |
| ⌘F1 / ⌘F2 | Keyboard backlight down / up |
| ⌃F1 / ⌃F2 | Dark mode / Light mode |
| F3 | App switcher: works like ⌘ of ⌘⇥ — tap to jump to the last app, hold + Tab to pick one |
| F6 (tap) | Toggle Do Not Disturb |
| F6 (hold) | Toggle Sleep Focus (or sleep / lock / caffeine — configurable) |
| fn / 🌐 (alone, in a text field) | Liquid Glass emoji picker at the caret, English + French search |
| fn / 🌐 double tap | Type the last emoji again |
| Caps Lock on | Caffeinated: no idle sleep, and no sleep with the lid closed |

Everything can be rebound or turned off in Settings. Keys that aren't bound pass straight through,
so fn+F4 and the rest of the top row behave like stock macOS.

## Build

```bash
./scripts/build.sh --install
```

Builds `build/Cool Tools.app`, signs it with your Apple Development identity (so the Accessibility
permission survives rebuilds), copies it to `/Applications` and launches it.

## First run

1. **Accessibility** — grant it when asked (System Settings → Privacy & Security → Accessibility).
2. **Karabiner** — quit it or remove its F1/F2 rules; Cool Tools does the same job.
3. **Lid closed** — Settings → Caffeine → *Set Up…* installs a sudoers rule that allows only
   `pmset -a disablesleep 0|1`.

## How the system bits work

- **Do Not Disturb** posts macOS' own “Turn Do Not Disturb On/Off” keyboard shortcut (assigning
  ⌃⌥⇧⌘F19 if it has none) — apps can't call the Focus service directly.
- **Sleep Focus** is toggled through Control Center's Focus list via Accessibility (Control Center
  flashes open for a moment). The mode is matched by macOS' own localized name for it.
- **🌐 key**: while the picker is on, macOS' “Press 🌐 key to” is set to *Do Nothing*; the previous
  choice comes back when the picker is turned off or the app quits.

## Releasing

```bash
scripts/release.sh 1.0.0         # Developer ID signed + notarized, published to GitHub
scripts/release.sh 1.0.0 --dev   # Apple Development signed, not notarized
```

The default mode needs a Developer ID Application certificate and a `cooltools-notary`
notarytool profile; the script's header explains the one-time setup.

## Regenerating data

```bash
python3 -I scripts/gen_emoji.py       # Resources/emoji.json from Unicode + CLDR (en, fr)
swift scripts/make_icon.swift         # Resources/AppIcon.icns from Assets/icon-source.jpg
```

`"/Applications/Cool Tools.app/Contents/MacOS/CoolTools" --selftest` prints what the emoji index,
backlight and caffeine helpers see on this Mac.
