# Omarchy Window Switcher

A native Omarchy Quattro overlay for switching between windows visible in the
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
omarchy plugin add https://github.com/rohan-patnaik/omarchy-window-switcher.git --enable
```

Back up `~/.config/hypr/bindings.lua`, then add this guarded include to it:

```lua
-- Omarchy Window Switcher (safe if the plugin is unavailable).
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

`Super+Q` is intentionally added without changing Omarchy's existing Alt+Tab
binding.

## Use

- Press and hold `Super`, then tap `Q` to cycle forward. Release `Super` to
  activate the selected window.
- Use `Shift+Q`, `Shift+Tab`, Left, or Up to move backward.
- Use `Q`, `Tab`, Right, or Down to move forward.
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

Removing the plugin does not modify the stock Alt+Tab behavior.

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

This project has not been submitted to the Omarchy plugin marketplace.

## License

MIT
