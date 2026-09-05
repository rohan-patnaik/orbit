# Omarchy Orbit

Orbit is a native Omarchy Quattro overlay for switching between windows visible across
all connected monitors. Grid and Flip keep separate windows from the same application
as separate entries. Browser tabs are outside the plugin's scope.

The plugin provides three modes:

- **Icons** — a macOS-style strip with one locally resolved official icon per
  application and its most recently used window as the activation target.
- **Flip** — an angled stack of window previews.
- **Grid** — an adaptive, aspect-aware thumbnail grid and the default mode.

Orbit also adds a Windows-inspired desktop layout layer:

- **Snap Layouts** — `Super+Z` opens seven choices on the active window's current
  monitor: halves, two thirds, thirds, wide center, quarters, Maximized, and
  Fullscreen. Main-and-stack has been removed.
- **Snap Assist** — after placing the active window, Orbit offers the other
  windows on that workspace for the remaining zones.
- **Window modes** — `Super+Shift+Z` chooses the default launch mode and can
  disable Omarchy's tiled, floating, maximized, fullscreen, or tiled-fullscreen
  shortcuts. At least one normal window mode always remains enabled.
- **Live drag picker** — the optional ABI-matched native bridge recognizes a real
  compositor move-drag from an application's titlebar (or `Super`+drag). The picker
  appears **while the button is still held** at the top edge or any screen corner.
  Move over a zone and release to apply it. Move away or press Escape to cancel.
  The preview takes neither keyboard focus nor pointer input from the drag.
- **Snap Groups** — windows placed together through Snap Assist are remembered
  for the current shell session. Alt+Tab raises the whole group before focusing
  the selected member. This is a small session-local grouping feature, not a
  complete implementation of Windows Snap Groups.

Grid and Flip use bounded, one-frame Quickshell window captures. Grid sizes cards
from the source aspect ratios to avoid artificial padding while keeping the whole
window visible. Letterboxing produced inside an app or video is retained. Captures are released when the
overlay closes and are never written to disk or sent over the network. Icons are
resolved from installed desktop entries and the local icon theme; Orbit does not
download icons. Icons mode chooses a light or dark backplate from the actual icon
pixels, including themed image-provider icons. A monogram is used when the icon is
missing or fails to load.

Each switch session is built from one fresh Hyprland client query ordered by
`focusHistoryID`. The active window is first, the last-used window is second, and
releasing Alt activates the current selection, matching Windows-style MRU cycling.
By default, Orbit combines the active workspace from every connected monitor into one
MRU list, while always rendering the Alt+Tab overlay on the primary display at the
compositor origin. Selecting a window focuses it in place without moving it between
monitors. Fullscreen handoffs
are isolated per workspace, so a fullscreen window on one display is never resized or
released merely because focus moved to another display.
Orbit also preserves fullscreen and maximized state per window. Before focus moves,
it temporarily separates Hyprland's layout state from the application's client-side
fullscreen state, then restores the destination window's own state as one guarded
activation transaction. Orbit keeps its overlay visible and suppresses handoff-only
window animations during resizing. It explicitly releases only the source's internal
fullscreen state **before** promoting the target, including fullscreen-to-fullscreen
switches. This avoids Hyprland implicitly cancelling the outgoing app's fullscreen.
The handoff is one live-state-checked compositor operation, not competing IPC and
foreign-toplevel activation requests. Retries are idempotent. With the native bridge,
the normal Hyprland bindings send presses, Alt-release boundaries and Escape through
one ordered event stream, keeping rapid independent gestures separate. Delayed events
from the UI cannot prematurely commit a newer native gesture. Held Alt does not expire
after ten seconds. Without the bridge, global shortcuts and modifier polling remain
available, including when the bridge is unloaded during a session.

Exact-address activation is followed by an explicit raise and confirmed against
Hyprland's active window before Orbit closes (direct compositor confirmation when the
bridge is loaded, rather than relying only on the shell's asynchronous cache). This prevents a fullscreen or obscured
window from swallowing Alt+Tab and leaving the user on the app they started from.
The keyboard-grabbing picker unmaps before activation; the passive resize cover is a
separate window. This avoids an initial-map/interactivity race that could leave a stale
exclusive grab and block every focus attempt. Orbit repeats the raise after the handoff, avoiding
the compositor restoring the old fullscreen surface above the newly active application.

On this Hyprland tiling layout, focus can transfer the workspace's active maximized or
fullscreen geometry, so the destination may still need to resize. Orbit starts that restore
before focus moves and keeps a frozen local capture of the outgoing window on screen.
The optional native bridge checks the destination's committed Wayland configure size,
not the size of a compositor screenshot (which can change before the app redraws).
Orbit reveals it after this confirmation and a short rendering guard. The cover lives
on the window's own monitor, independently of the main-display picker.
If the bridge is unavailable, the app is XWayland, or the app never commits the requested
size, a bounded 1.6-second fallback prevents a permanently stuck cover. That fallback
is not a promise of flicker-free rendering in every app. Orbit cannot inspect a site's
internal video/GPU pipeline or reproduce the Windows compositor exactly.

## Requirements

- Omarchy Quattro with plugin support
- Hyprland
- Quickshell with `ScreencopyView`

## Install

Install and enable the plugin:

```bash
omarchy plugin add https://github.com/rohan-patnaik/orbit.git --enable
```

Back up `~/.config/hypr/bindings.lua`, then add this guarded include to it:

```lua
-- Orbit (safe if the plugin is unavailable).
local window_switcher_bindings = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/bindings.lua"
local window_switcher_file = io.open(window_switcher_bindings, "r")
if window_switcher_file then
  window_switcher_file:close()
  dofile(window_switcher_bindings)
end
```

Apply the binding and confirm Hyprland accepted it:

```bash
hyprctl reload
hyprctl configerrors
```

For native titlebar/top-edge drag integration, build the small Hyprland bridge
against the compositor currently installed on the machine, then load it:

```bash
bash ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/scripts/build-native.sh
hyprctl plugin load ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/native/orbit-drag.so
hyprctl plugin list
```

Hyprland plugins run inside the compositor and have no stable ABI. Orbit checks
the Hyprland build hash at load time and refuses a mismatch; the build helper
also reports the compositor's full ABI string. Rebuild this bridge after each
Hyprland upgrade. Omarchy's marketplace installer intentionally never executes
install hooks, so marketplace updates do not compile it automatically; Super+Z,
Snap Assist, Snap Groups, and core Alt+Tab behavior work without the bridge. Live drag
discovery and the stronger Wayland surface-readiness check require it.
Precise queued Alt-release/cancellation handling and app fullscreen-exit notifications
also use this bridge. It does not record typed text.

Orbit replaces Omarchy's stock `Alt+Tab` bindings. The stock direct window
cycling behavior remains available on `Super+Q` and `Super+Shift+Q`.

## Use

- Press and hold `Alt`, then tap `Tab` to cycle forward. Release `Alt` to
  activate the selected window.
- Use `Alt+Shift+Tab`, `Shift+Tab`, Left, or Up to move backward.
- Use `Tab`, Right, or Down to move forward.
- Use `Super+Q` or `Super+Shift+Q` for Omarchy's original direct window cycle.
- Press `Super+Z` to choose a snap layout for the active window. Click a zone or
  choose it with the arrow keys and Enter; Snap Assist then fills the open zones.
- With the optional native bridge loaded, drag a window by its own titlebar or
  with `Super`+left-drag to the top edge or a screen corner. Keep holding, move
  onto the desired zone, then release. Resize grips, text selection, and simply
  moving the pointer near an edge do not activate the picker.
- Press `Super+Shift+Z` to choose the default launch mode and enabled window-mode
  shortcuts. Changes take effect on the next window after Hyprland reloads.
- Press `1`, `2`, or `3` to select Icons, Flip, or Grid. The choice is saved in
  `~/.config/omarchy/shell.json`.
- Press Enter or Space, or click a window, to activate it.
- Press Escape or click outside the switcher to cancel.

**Maximized** means work-area filling (`Super+Alt+F`), retaining the bar, rather
than true fullscreen (`Super+F`). Fresh installations keep Omarchy's tiled default.
If you choose Maximized as your personal default, ordinary new windows use it;
the optional maximize-on-switch setting also applies it to normal tiled windows on
activation. Intentional floating dialogs, PiP, and snapped windows are exempt. With
the native bridge, a normal Wayland app voluntarily leaving media fullscreen returns
to that Maximized default. Manual mode shortcuts and snap choices remain available.

For a latched switcher that does not depend on holding `Super`:

```bash
omarchy-shell shell summon io.github.rohan-patnaik.window-switcher '{"action":"show"}'
```

## Remove

Remove the guarded include shown above from `~/.config/hypr/bindings.lua`, then
run:

```bash
omarchy plugin remove io.github.rohan-patnaik.window-switcher
hyprctl reload
hyprctl configerrors
```

Removing the guarded include restores Omarchy's stock Alt+Tab behavior on the
next Hyprland reload. Orbit retains the internal plugin ID
`io.github.rohan-patnaik.window-switcher` so existing installations and saved
mode preferences continue to work after the public rename.

If the native bridge is loaded, unload it before removing Orbit:

```bash
hyprctl plugin unload ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/native/orbit-drag.so
```

### Window scope

The default `visible` scope matches a Windows-style extended desktop: Orbit includes
the active workspace on every connected monitor. The plugin entry in
`~/.config/omarchy/shell.json` can optionally set `scope` to `monitor` for only the
invoking monitor, or `all` for every normal numbered or named workspace. Hidden special
workspaces remain excluded from `all`.

```json
{
  "id": "io.github.rohan-patnaik.window-switcher",
  "mode": "grid",
  "scope": "visible",
  "overlayMonitor": "primary",
  "windowModes": {
    "defaultMode": "maximized",
    "maximizeOnSwitch": true,
    "tiled": true,
    "floating": true,
    "maximized": true,
    "fullscreen": true,
    "tiledFullscreen": true
  }
}
```

`overlayMonitor` defaults to `primary`, the monitor positioned at `0x0` in the
Hyprland layout. Set it to an exact output name such as `HDMI-A-1` to pin the
switcher there explicitly, or to `focused` to restore the previous behavior.
This controls only where the Alt+Tab UI appears; app eligibility still follows
`scope`, and Snap Layouts continue to open on the window being arranged.

The example above is an **opt-in personal preference**. A fresh installation keeps
Omarchy's normal tiled default and does not maximize on switch automatically.

The window-mode policy controls Orbit's default launch rule, Alt+Tab behavior,
and the standard Omarchy shortcuts. `maximized` is Hyprland's standard name for
the work-area-filling mode behind `Super+Alt+F`. With `maximizeOnSwitch` enabled,
normal tiled windows enter that mode when selected, while intentional floating,
snapped, pinned, dialog/PiP windows retain their geometry. Existing client or
compositor fullscreen state is restored unchanged. Browser video, VLC, games,
and presentation software can therefore still request true fullscreen.
Disabling a mode removes its Orbit shortcut/picker option; it does not globally
forbid an application or another plugin from requesting that mode. These preferences
do not override explicit background-launch protections or application-specific rules.

## Development checks

```bash
bash scripts/check.sh
```

During development, link this repository to the user plugin directory and
enable it with Omarchy's plugin command. If source changes are not picked up
automatically, run `omarchy restart shell`.

Useful diagnostics:

```bash
omarchy plugin validate .
omarchy-shell orbit-diagnostics state
hyprctl orbit-drag-status
hyprctl orbit-window-ready 0xWINDOW_ADDRESS
omarchy-shell shell rescanPlugins
omarchy restart shell
journalctl --user -u omarchy-shell.service -n 100 --no-pager
```

The root `preview.png` is the original monochrome marketplace mark for this
plugin listing.

The [0.6.0 validation report](docs/AUDIT-2026-09-05.md) distinguishes automated
regressions, live compositor tests, and remaining release checks. This candidate
has not been submitted to the marketplace.

## License

MIT
