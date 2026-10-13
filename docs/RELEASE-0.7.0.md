# Orbit 0.7.0 — dock and desktop controls

Orbit now bundles the application dock, with pinned/running apps, installed
icons, hover previews, minimize/restore, grouped windows and persistent drag
ordering. The bar module uses Orbit's Dock.qml; the migration helper preserves
an existing taskbar's ID, pins, order and unrelated shell preferences.

Super+Shift+Z opens Desktop controls. Application dock, Grid, Flip and Icons
are independent switches. The dock and all three views default to enabled after
placement; missing feature preferences retain these defaults. Disabled views
cannot be selected by numeric shortcuts or mode pills. Disabling the current
view selects an enabled one. With all three off, Alt+Tab still activates the MRU
window and restores minimized/fullscreen state without mapping the picker.

Feature-only saves take effect through the watched configuration without a
compositor reload. Window-mode policy changes still reload their bindings.
Failed saves leave the dialog open with an error and preserve the active policy.
The settings page fits the display and scrolls on smaller screens.

## Upgrade

Update/enable the plugin through the existing Omarchy mechanism, retain your
guarded bindings include, and run `scripts/install-dock.py --backup-dir PATH`.
Inspect `--dry-run` first when adapting a different bar layout. This does not
rebuild or change the native bridge; preserve your ABI-matched bridge and local
compositor adaptations. Use `--remove` before deleting Orbit to restore the
previous dock source while keeping pins added since installation.

## Validation

Node tests execute the actual overlay method bodies and cover defaults,
independent switches, disabled views, all-views-off MRU activation, scoped-facade
preferences, saved metadata and failed writes. Python tests exercise reversible
layout migration and preservation of later pin changes. The native Qt lifecycle
regression tests initial visibility, unload/re-enable, popup-owner identity and
plugin disablement. Standard plugin, QML and formatting gates remain in
`scripts/check.sh`. The live integration and recording results are recorded
separately; a desktop recording is a feature demonstration, not a latency benchmark.
