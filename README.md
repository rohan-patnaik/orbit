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

- **Snap Layouts** — `Super+Z` opens six layouts on the active window's current
  monitor, including halves, thirds, a main-plus-stack layout, and quarters.
- **Snap Assist** — after placing the active window, Orbit offers the other
  windows on that workspace for the remaining zones.
- **Window modes** — `Super+Shift+Z` chooses the default launch mode and can
  disable Omarchy's tiled, floating, full-width, fullscreen, or tiled-fullscreen
  shortcuts. At least one normal window mode always remains enabled.
- **Top-edge drag** — the optional ABI-matched native bridge recognizes a real
  compositor move-drag from an application's titlebar (or `Super`+drag). Drop
  the window at the top edge and Orbit opens the same Snap Layout chooser.
- **Snap Groups** — windows placed together through Snap Assist are remembered
  for the current shell session. Alt+Tab raises the whole group before focusing
  the selected member, matching Windows' grouped restore behavior.

Grid and Flip use bounded, one-frame Quickshell window captures. Grid sizes each
card to the source window's aspect ratio, so the full capture fills the preview
without cropping, stretching, or letterboxing. Captures are released when the
overlay closes and are never written to disk or sent over the network. Icons are
resolved from installed desktop entries and the local icon theme; Orbit does not
download icons. A unique application monogram is used only when no icon is available.

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
window animations until the destination is ready, so intermediate tiled geometry is
never exposed. Fullscreen browser video therefore remains fullscreen when switching
away and back without a tiled-layout flash.

Exact-address activation is followed by an explicit raise and confirmed against
Hyprland's active window before Orbit closes. This prevents a fullscreen or obscured
window from swallowing Alt+Tab and leaving the user on the app they started from.
Orbit repeats the raise after its keyboard-grabbing overlay has fully unmapped, avoiding
the compositor restoring the old fullscreen surface above the newly active application.

On this Hyprland tiling layout, focus can transfer the workspace's active maximized or
fullscreen geometry, so the destination may still need to resize. Orbit starts that restore
before focus moves and keeps a frozen local capture of the outgoing window on screen.
A hidden live probe waits for the destination to submit a surface at its new size; Orbit
then reveals it after a short two-frame guard. This makes the transition visually atomic
instead of exposing a partial old-size frame from a GPU-rendered browser or desktop app.
The protection is application-agnostic, so it also covers other video sites, documents,
terminals, and Electron-style applications.

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
Snap Assist, Snap Groups, and all Alt+Tab behavior work without the bridge.

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
- With the optional native bridge loaded, drag a window by its own titlebar to
  the top edge and release it to open that same chooser on its current monitor.
- Press `Super+Shift+Z` to choose the default launch mode and enabled window-mode
  shortcuts. Changes take effect on the next window after Hyprland reloads.
- Press `1`, `2`, or `3` to select Icons, Flip, or Grid. The choice is saved in
  `~/.config/omarchy/shell.json`.
- Press Enter or Space, or click a window, to activate it.
- Press Escape or click outside the switcher to cancel.

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
invoking monitor, or `all` for every normal numbered workspace. Hidden special
workspaces remain excluded from `all`.

```json
{
  "id": "io.github.rohan-patnaik.window-switcher",
  "mode": "grid",
  "scope": "visible",
  "overlayMonitor": "primary",
  "windowModes": {
    "defaultMode": "maximized",
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

The window-mode policy controls Orbit's default launch rule and the standard
Omarchy shortcuts. It intentionally does not reject application-requested
fullscreen, so browser video, games, and presentation software keep working.

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
omarchy-shell shell rescanPlugins
omarchy restart shell
journalctl --user -u omarchy-shell.service -n 100 --no-pager
```

The root `preview.png` is the original monochrome marketplace mark for this
plugin listing.

## License

MIT
