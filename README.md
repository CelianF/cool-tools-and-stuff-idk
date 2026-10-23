# Cool Tools

<img src="Assets/icon-1024.png" width="128" align="right">

A tiny SwiftUI menu bar app that replaces my Karabiner-Elements setup and adds a few extras.

| Key | Does |
| --- | --- |
| ⌘F1 / ⌘F2 | Keyboard backlight down / up |
| ⌃F1 / ⌃F2 | Dark mode / Light mode |
| F6 (tap) | Toggle Do Not Disturb |
| F6 (hold) | Toggle Sleep Focus (or sleep / lock / caffeine — configurable) |
| fn / 🌐 (alone) | Liquid Glass emoji picker, English + French search |
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
3. **🌐 key** — System Settings → Keyboard → “Press 🌐 key to” → **Do Nothing**, so only Cool Tools' picker opens.
4. **Focus** — Settings → Focus → *Install* adds two helper Shortcuts. macOS only lets apps toggle
   Focus modes through Shortcuts.
5. **Lid closed** — Settings → Caffeine → *Set Up…* installs a sudoers rule that allows only
   `pmset -a disablesleep 0|1`.

## Regenerating data

```bash
python3 -I scripts/gen_emoji.py       # Resources/emoji.json from Unicode + CLDR (en, fr)
swift scripts/make_icon.swift         # Resources/AppIcon.icns from Assets/icon-source.jpg
python3 -I scripts/make_shortcuts.py  # signed helper Shortcuts in Resources/Shortcuts
```

`"/Applications/Cool Tools.app/Contents/MacOS/CoolTools" --selftest` prints what the emoji index,
backlight and caffeine helpers see on this Mac.
