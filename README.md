# Omarchy Orbit

Orbit provides a native Omarchy Quattro application dock and visual window switching
across connected monitors. All three views keep separate windows from the same application
as separate entries. Browser tabs are outside the plugin's scope.

## At a glance

- Keep a familiar application dock with pins, running apps, hover previews, minimize/restore and saved ordering.
- Toggle the dock, Task Manager, Grid, Flip and Icons independently in **Super+Shift+Z → Desktop controls**. All three views start enabled.
- Switch the windows on every connected monitor from one focused, keyboard-first overlay.
- Choose **Grid**, **Flip**, or **Icons**—each designed to keep individual windows visible and recognisable.
- Use **Snap Layouts** and **Snap Assist** to place windows quickly without leaving the keyboard.
- Resolve icons and captures locally; Orbit does not download window data or write captures to disk.

The plugin provides three modes:

- **Icons** — a strip with one locally resolved official icon per window.
  Repeated applications receive numbered labels; each icon activates its own window.
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

Orbit reduces work on the switching path: ordinary switches
use a 16 ms initial unmap timer, then advance as soon as the compositor confirms
focus. Resize handoffs retain their 40 ms capture head start and 80 ms rendering
guard. These are configured waits, not measured end-to-end latency guarantees.
Native Alt holds need no modifier-polling processes; unloading the bridge restores
the fallback. Native gestures wait 75 ms after the window query before presenting
the picker, while release activates immediately. Quick taps avoid the picker and
its captures entirely. Ordinary tiled switches allocate no full-screen handoff
capture. Resize covers wait for capture content and freeze immediately before
activation. Orbit's picker and cover bypass compositor fades. Flip retains the
previews already in view and updates selection without continuous animation.

The capture count is bounded, but capture memory is still affected by the source
window resolution: Quickshell's `constraintSize` controls display sizing, not a
lower-resolution capture buffer. Grid limits itself to 12 previews per page and
Flip to seven visible previews; they remain still images to avoid continuous
capture work. See the [performance validation](docs/PERFORMANCE-2026-09-05.md) for
the measured desktop latency, captured transitions, resource results, and limits.

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

## Dock and view controls

Orbit 0.7.0 bundles the application dock previously maintained separately for
this desktop. The dock groups running windows, resolves installed application
icons, supports hover previews, pin/unpin and drag ordering, and minimizes or
restores an application. Running and minimized windows from normal workspaces
on connected displays remain available; utility/special windows stay excluded.

Place it once after installing/enabling Orbit:

```bash
python3 ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/scripts/install-dock.py --backup-dir /path/to/recovery
```

Choose your recovery directory first. `--dry-run` prints the planned bar layout.
An existing `taskbar` entry keeps its pins, ordering, position and other settings;
only its component source changes. A new dock is added to the center without
removing other widgets. The clock, tray and other bar widgets stay independent.
The native bridge is optional and does not need rebuilding for this update.

**Super+Shift+Z** opens **Desktop controls**. Its five independent checkboxes are
**Application dock**, **Grid**, **Flip**, **Icons** and **Task Manager**. Press **Apply** to save.
Turning the dock off unloads its widget and popups; turning it on recreates them
without losing pins or ordering. The three visual views default to enabled,
including existing installations whose settings have no `features` object.
Disabled views are omitted from the picker and cannot be selected with 1/2/3.
If a saved view is disabled, Orbit chooses an enabled one. All three can be off:
Alt+Tab still uses Orbit's MRU activation/restoration with no visual picker.
The window-mode controls below continue to configure Maximized, Floating,
Tiled and Fullscreen independently.

The saved plugin entry may contain:

```json
"features": { "dock": true, "grid": true, "flip": true, "icons": true, "taskManager": true }
```

Before removing Orbit, restore the previous dock component first:

```bash
python3 ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/scripts/install-dock.py --remove --backup-dir /path/to/recovery
```

This restores only the previous source/type and preserves current pins and
ordering. If Orbit added a new dock, its settings are retained in
`bar.orbitDockSettings` for a later reinstall. Installation backups are recovery
evidence; do not replace a newer whole shell configuration with an old backup.

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
- Press `Super+Shift+Z` to toggle the dock/views and choose the default launch mode
  and enabled window-mode shortcuts. Dock/view changes apply immediately; window-mode
  policy changes reload bindings and set the next window's behavior.
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

Run the dock removal command above before removing the plugin files.

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

The root `preview.png` is the marketplace cover for this plugin listing.

The [0.6.2 release notes](docs/RELEASE-0.6.2.md) describe the patch and upgrade steps.
The [performance validation](docs/PERFORMANCE-2026-09-05.md) records the measured
latency, resource use, live regression checks, and remaining limits. Marketplace
promotion is tracked separately in the [exact-commit update request](https://github.com/omacom/omarchy-plugin-marketplace/issues/11365).

## License

MIT

The [0.6.4 compatibility notes](docs/RELEASE-0.6.4.md) cover web-app icons and
extended taskbar minimize records. Taskbar icon ordering stays in the taskbar;
Orbit retains MRU window switching.

The [0.7.0 release notes](docs/RELEASE-0.7.0.md) describe the bundled dock, independent feature switches and migration.


## Task Manager (0.8.0)

Orbit bundles a polished, current-theme Xfce Task Manager integration. After
installing the official package with `omarchy pkg add xfce4-taskmanager`, the
existing Orbit bindings include gives **Ctrl+Shift+Esc** its graphical task list.
Reload Hyprland once after upgrading bindings. No native bridge rebuild is needed.

**Super+Shift+Z → Desktop controls → Task Manager** defaults to on, including
older configurations with no saved flag. Apply saves `features.taskManager`.
Off means Ctrl+Shift+Esc opens btop. A disabled/unlisted Orbit entry, unreadable
configuration, or missing Xfce application also uses btop. **Super+Ctrl+T** stays
unchanged. Toggle changes take effect on the next launch without a shell reload
and never terminate an already-open Task Manager or any other process.

The bundled launcher seeds missing search/PID/state/CPU/memory columns while
preserving saved display preferences, and enables termination confirmation.
Use Terminate first; Kill only if necessary. Lifecycle colours mean starting,
changing and terminating, not hung-app detection. Escape closes the main window.
A frozen compositor may prevent any graphical shortcut; try Ctrl+Alt+F3 and an
orderly reboot if a console responds. Orbit does not change drivers or power policy.

The private GTK3 theme reads the active Omarchy semantic palette on every launch.
Toolbar/search, headers, row spacing, selection, menus and dialogs support dark
and light palettes. Native icon theme, lifecycle highlights and graph colours
stay intact. No global GTK settings, vendor binary or system files are modified.
Close/reopen an existing window after switching themes. If theme generation fails,
Task Manager still opens using native GTK. Python 3 and Omarchy are runtime
requirements; xfconf-query is supplied by the Xfce dependency chain. Install the
optional package explicitly: store installation never elevates privileges or runs
an installer hook. Without it, the working btop fallback remains available.

The launcher can also be used directly:
`python3 ~/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/scripts/task-manager.py`.
Before removing Orbit, remove its bindings include and reload Hyprland. Integrators
may route an Apps desktop entry to the same command; no additional daemon is needed.

See [0.8.0 release notes](docs/RELEASE-0.8.0.md) for this update.

The [0.8.1 patch](docs/RELEASE-0.8.1.md) also renders taskbar application metadata
as literal plain text, addressing the marketplace context-menu review.
