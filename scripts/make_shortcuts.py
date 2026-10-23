#!/usr/bin/env python3
"""Builds the signed helper Shortcuts the app uses to toggle Focus modes (macOS has no public Focus API).

Usage: python3 -I scripts/make_shortcuts.py   (needs network: `shortcuts sign` talks to Apple)
"""
import os
import plistlib
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Shortcuts")
FOCUSES = {
    "Cool Tools - Toggle Do Not Disturb": ("com.apple.donotdisturb.mode.default", "Do Not Disturb", 59511),
    "Cool Tools - Toggle Sleep Focus": ("com.apple.sleep.sleep-mode", "Sleep", 59458),
}


def workflow(identifier, display, glyph):
    return {
        "WFWorkflowClientVersion": "2605",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": glyph},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowActions": [{
            "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
            "WFWorkflowActionParameters": {
                "Operation": "Toggle",
                "Enabled": 1,
                "FocusModes": {"Identifier": identifier, "DisplayString": display},
            },
        }],
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, args in FOCUSES.items():
            unsigned = os.path.join(tmp, "unsigned.shortcut")
            with open(unsigned, "wb") as f:
                plistlib.dump(workflow(*args), f, fmt=plistlib.FMT_BINARY)
            out = os.path.join(OUT, f"{name}.shortcut")
            subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", unsigned, "--output", out], check=True)
            print("wrote", out)


if __name__ == "__main__":
    main()
