# Omarchy Orbit

Orbit is a native Omarchy Quattro overlay for switching between windows visible in the
current workspace. Separate windows from the same application remain separate
entries. Browser tabs are outside the plugin's scope.

The plugin provides three modes:

- **Icons** — a compact icon strip with one entry per window.
- **Flip** — an angled stack of window previews.
- **Grid** — an adaptive thumbnail grid and the default mode.

Grid and Flip use bounded, one-frame Quickshell window captures. Captures are
released when the overlay closes and are never written to disk or sent over the
network. A window's application icon is shown if its preview is unavailable.

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
