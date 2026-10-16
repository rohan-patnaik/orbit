# Orbit 0.8.0 — themed Task Manager

Adds the polished Omarchy-palette Xfce Task Manager to Orbit. Its Desktop controls
checkbox is enabled by default. Ctrl+Shift+Esc opens the GUI when enabled and
installed; off, disabled Orbit or missing Xfce uses btop. Super+Ctrl+T is unchanged.
The setting is read on each invocation, so applying it needs no compositor reload.
Existing windows are never closed by a toggle.

Includes theme-derived toolbar/search, headers, readable table rows, selection,
menus and dialogs in light and dark palettes. Scope is this application alone.
Native lifecycle indicators/graphs retain their meanings. Search and resource/state
columns are seeded only when absent; termination confirmation is enabled on launch.
No automatic process termination, driver or power-policy changes.

## Upgrade

Update Orbit, install `xfce4-taskmanager` with the supported Omarchy package workflow
if wanted, and reload the existing guarded Orbit bindings include once. Confirm
`hyprctl configerrors` is empty. No native bridge rebuild. Missing package falls
back to btop; plugin installation does not silently install packages or run hooks.
Reopen Task Manager after switching themes. Full installation details are in README.

GitHub publication and marketplace verified-snapshot promotion are separate.

Feature pointer taps now claim their gesture, preventing the background dismiss
handler from closing Desktop controls before Apply. Keyboard toggles remain supported.

## Validation

Release checks passed: 112 Node tests, 13 Python/Qt tests, plugin validation,
QML lint/format gates and whitespace checks. Existing nonfatal QML lint warnings
remain. The pointer regression executes the real feature component in Qt and
checks that a toggle does not also dismiss the backdrop. Launcher tests cover
saved defaults/off, plugin disablement, missing GUI, palette failure/timeout,
preference preservation and required termination confirmation.

On the maintained Omarchy desktop, Cua verified the visible default-on checkbox,
keyboard off + Apply, Ctrl+Shift+Esc opening btop, pointer on + Apply staying open
until saved, and Ctrl+Shift+Esc opening the themed GUI. The preference was left on;
other saved settings are byte-equivalent after excluding the new flag. Only the
owned test viewers were closed. Installed local adaptations passed 104 Node and
13 Python tests. OMA passed 438 catalog entries and 289 unique tests across a full
run and two storage-dependent fixture reruns on the outer artifact volume.
