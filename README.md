# Omarchy Orbit

Orbit is a native Omarchy Quattro overlay for switching between windows visible in the
current workspace. Grid and Flip keep separate windows from the same application as
separate entries. Browser tabs are outside the plugin's scope.

The plugin provides three modes:

- **Icons** — a macOS-style strip with one locally resolved official icon per
  application and its most recently used window as the activation target.
- **Flip** — an angled stack of window previews.
- **Grid** — an adaptive, aspect-aware thumbnail grid and the default mode.

Grid and Flip use bounded, one-frame Quickshell window captures. Grid sizes each
card to the source window's aspect ratio, so the full capture fills the preview
without cropping, stretching, or letterboxing. Captures are released when the
overlay closes and are never written to disk or sent over the network. Icons are
resolved from installed desktop entries and the local icon theme; Orbit does not
download icons. A unique application monogram is used only when no icon is available.

Each switch session is built from one fresh Hyprland client query ordered by
`focusHistoryID`. The active window is first, the last-used window is second, and
releasing Alt activates the current selection, matching Windows-style MRU cycling.
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

Orbit replaces Omarchy's stock `Alt+Tab` bindings. The stock direct window
cycling behavior remains available on `Super+Q` and `Super+Shift+Q`.

## Use

- Press and hold `Alt`, then tap `Tab` to cycle forward. Release `Alt` to
  activate the selected window.
- Use `Alt+Shift+Tab`, `Shift+Tab`, Left, or Up to move backward.
- Use `Tab`, Right, or Down to move forward.
- Use `Super+Q` or `Super+Shift+Q` for Omarchy's original direct window cycle.
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
