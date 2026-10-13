#!/usr/bin/env python3
"""Place Orbit's dock in the bar while retaining existing taskbar metadata."""
import argparse
import copy
import json
from pathlib import Path
import shutil
import tempfile
import time

PLUGIN_ID = "io.github.rohan-patnaik.window-switcher"
DOCK_SOURCE = f"~/.config/omarchy/plugins/{PLUGIN_ID}/Dock.qml"


def dock_configuration(config, remove=False):
    result = copy.deepcopy(config)
    bar = result.setdefault("bar", {})
    layout = bar.setdefault("layout", {})
    found = False
    for section in ("left", "center", "right"):
        entries = layout.setdefault(section, [])
        replacements = []
        for entry in entries:
            if not isinstance(entry, dict) or entry.get("id") != "taskbar":
                replacements.append(entry)
                continue
            found = True
            replacement = dict(entry)
            if remove:
                if entry.get("source") != DOCK_SOURCE:
                    replacements.append(entry)
                    continue
                previous = entry.get("orbitPreviousDock")
                if not isinstance(previous, dict):
                    raise ValueError("Previous dock metadata is missing; restore only its source/type from the installation backup")
                replacement.pop("orbitPreviousDock", None)
                if previous.get("added") is True:
                    # Retain pins added since installation for a later reinstall.
                    bar["orbitDockSettings"] = {key: value for key, value in replacement.items() if key not in ("id", "type", "source")}
                    continue
                for key in ("type", "source"):
                    if previous.get(key + "Present") is True:
                        replacement[key] = previous.get(key)
                    else:
                        replacement.pop(key, None)
            elif entry.get("source") != DOCK_SOURCE:
                if "orbitPreviousDock" in entry:
                    raise ValueError("Existing dock restoration metadata conflicts with this installation")
                replacement["orbitPreviousDock"] = {
                    "added": False,
                    "typePresent": "type" in entry,
                    "sourcePresent": "source" in entry,
                    "type": entry.get("type"),
                    "source": entry.get("source"),
                }
                replacement.update(type="qml", source=DOCK_SOURCE)
            replacements.append(replacement)
        layout[section] = replacements
    if not found and not remove:
        entry = copy.deepcopy(bar.get("orbitDockSettings", {}))
        entry.update(id="taskbar", type="qml", source=DOCK_SOURCE, orbitPreviousDock={"added": True})
        layout["center"].append(entry)
        bar.setdefault("centerAnchor", "taskbar")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path.home() / ".config/omarchy/shell.json")
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--remove", action="store_true", help="Restore the previous dock source while retaining current pins and ordering")
    args = parser.parse_args()
    path = args.config.expanduser()
    if path.is_symlink():
        parser.error("Refusing a symlinked shell configuration")
    original = path.read_bytes()
    current = json.loads(original)
    updated = dock_configuration(current, args.remove)
    if updated == current:
        print("Dock configuration is already current; pins and ordering are unchanged.")
        return
    if args.dry_run:
        print(json.dumps(updated["bar"], indent=2))
        return
    args.backup_dir.mkdir(parents=True, exist_ok=True)
    backup = args.backup_dir / f"shell-before-orbit-dock-{time.time_ns()}.json"
    backup.write_bytes(original)
    # Tiny same-directory atomic write; preserve file permissions.
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".orbit-dock-", delete=False) as tmp:
        temporary = Path(tmp.name)
        tmp.write((json.dumps(updated, indent=2) + "\n").encode())
    try:
        shutil.copymode(path, temporary)
        if path.read_bytes() != original:
            raise RuntimeError("Shell configuration changed during installation; retry after reviewing it")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    if json.loads(path.read_bytes()) != updated:
        raise RuntimeError("Dock configuration readback failed")
    print(f"Dock configuration updated. Previous configuration: {backup}")


if __name__ == "__main__":
    main()
