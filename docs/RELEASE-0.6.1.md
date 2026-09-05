# Orbit 0.6.1

This patch packages the validated Alt+Tab performance and reliability fixes for
Omarchy Quattro. It also includes the 0.6.0 live snap picker and fullscreen handoff
work since the previous GitHub release, 0.5.0.

## Changes

- Quick native Alt+Tab taps activate without flashing the picker or allocating its
  thumbnails. Held Alt still presents the picker and supports reverse cycling.
- Ordinary tiled switching advances on confirmed compositor focus and avoids a
  full-screen handoff capture. Resizing transitions retain their capture and render
  guards, with no compositor fade on Orbit's picker or cover.
- Native Alt holds use release events instead of modifier-polling subprocesses.
  Flip preserves existing previews while cycling; Grid navigation crosses pages.
- Escape cancels queued gestures. Closing the destination during activation clears
  the picker and restores a surviving fullscreen source.
- The live snap picker appears during titlebar/top-edge dragging when the optional
  native bridge is loaded. Ordinary pointer movement no longer arms its drag sampler.
- CI installs Lua, a C++ compiler, and Quickshell in an Arch Linux container so the
  native and actual offscreen QML tests run alongside the JavaScript tests.

## Validation

The optimized implementation passed 87 automated tests, including the real QML
lifecycle fixture's 55 assertions, plus 30 live regression scenarios and additional
fullscreen, media, and drag checks. On the measured native Wayland desktop, median
Alt-release-to-focus latency for tiled windows fell from 67.55 to 21.71 ms. The
repeated-switch workload used about 70% less whole-Quickshell-plus-children CPU.
These are measurements on one setup, not universal latency or whole-computer savings.

The [performance report](PERFORMANCE-2026-09-05.md) contains methods, recorded
transition analysis, and limitations. XWayland resizing still uses the 1.6-second
fallback. Previews remain static, and no reliable RAM, battery, or complete Windows
11 parity claim is made. The patch's runtime behavior is the measured implementation;
release preparation changes its version metadata, documentation, and CI environment.

## Upgrade

For an existing git-managed installation:

```bash
omarchy plugin update io.github.rohan-patnaik.window-switcher --yes
```

Keep the guarded `bindings.lua` include described in the [installation guide](../README.md#install).
After updating, reload Hyprland's bindings and check for configuration errors:

```bash
hyprctl reload
hyprctl configerrors
```

The optional native bridge must be rebuilt for the installed Hyprland ABI. Marketplace
updates do not compile or reload it. If the old `orbit-drag` bridge is loaded, unload
it before replacing its binary; then rebuild and load the updated bridge:

```bash
hyprctl plugin list
# Run only if orbit-drag is loaded:
hyprctl plugin unload ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/native/orbit-drag.so
bash ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/scripts/build-native.sh
hyprctl plugin load ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/native/orbit-drag.so
```

Core switching, Super+Z, Snap Assist, and Snap Groups work without this bridge.
Live drag discovery, ordered native release handling, and stronger Wayland readiness
checks require it. See the installation guide for requirements and removal.

## Distribution

GitHub release: [v0.6.1](https://github.com/rohan-patnaik/orbit/releases/tag/v0.6.1).
Marketplace publication and exact-snapshot approval are tracked in
[update request #4612](https://github.com/omacom/omarchy-plugin-marketplace/issues/4612).
The store's install/update commands obtain the repository's current upstream HEAD;
they are separate from approval of a particular marketplace snapshot.
