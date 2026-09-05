-- Orbit replaces Omarchy's stock Alt+Tab bindings. Keep the original
-- window-cycle behavior available on Super+Q.
local orbit_plugin_id = "io.github.rohan-patnaik.window-switcher"

local function orbit_window_modes()
  local modes = {
    default_mode = "tiled",
    tiled = true,
    floating = true,
    maximized = true,
    fullscreen = true,
    tiled_fullscreen = true,
  }
  local home = os.getenv("HOME") or ""
  local config_path = home .. "/.config/omarchy/shell.json"
  local query = [[
    ([.plugins[]? | select(.id == $id) | .windowModes][0] // {}) as $m
    | [
        ($m.defaultMode // "tiled"),
        (if $m | has("tiled") then $m.tiled else true end),
        (if $m | has("floating") then $m.floating else true end),
        (if $m | has("maximized") then $m.maximized else true end),
        (if $m | has("fullscreen") then $m.fullscreen else true end),
        (if $m | has("tiledFullscreen") then $m.tiledFullscreen else true end)
      ] | @tsv
  ]]
  local command = "jq -r --arg id " .. o.shell_quote(orbit_plugin_id)
    .. " " .. o.shell_quote(query) .. " " .. o.shell_quote(config_path) .. " 2>/dev/null"
  local pipe = io.popen(command)
  if not pipe then
    return modes
  end
  local line = pipe:read("*l") or ""
  pipe:close()
  local values = {}
  for value in (line .. "\t"):gmatch("([^\t]*)\t") do
    table.insert(values, value)
  end
  if #values == 6 then
    modes.default_mode = values[1]
    modes.tiled = values[2] == "true"
    modes.floating = values[3] == "true"
    modes.maximized = values[4] == "true"
    modes.fullscreen = values[5] == "true"
    modes.tiled_fullscreen = values[6] == "true"
  end
  if not modes.tiled and not modes.floating and not modes.maximized then
    modes.maximized = true
  end
  if modes.default_mode ~= "tiled" and modes.default_mode ~= "floating" and modes.default_mode ~= "maximized" then
    modes.default_mode = "maximized"
  end
  if not modes[modes.default_mode] then
    modes.default_mode = modes.maximized and "maximized" or (modes.tiled and "tiled" or "floating")
  end
  return modes
end

local window_modes = orbit_window_modes()

local function orbit_cycle(direction)
  -- Look up on every invocation so loading/unloading the optional native
  -- bridge does not strand the binding. The native path keeps presses and
  -- Alt releases in one ordered event stream, including rapid gestures.
  local bridge = hl.plugin and hl.plugin.orbit
  if bridge and bridge[direction] then
    bridge[direction]()
  else
    hl.dispatch(hl.dsp.global("omarchy-window-switcher:" .. direction))
  end
end

-- Do not override app/Omarchy rules for dialogs, PiP, transient utility windows
-- or the user's background-launch rules. Tiled is the unmodified default.
if window_modes.default_mode == "floating" then
  o.window({ class = ".*", float = false }, { float = true })
elseif window_modes.default_mode == "maximized" then
  o.window({ class = ".*", float = false }, { maximize = true })
end

hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

o.bind(
  "ALT + TAB",
  "Orbit next window",
  function() orbit_cycle("next") end,
  { repeating = true }
)

o.bind(
  "ALT + SHIFT + TAB",
  "Orbit previous window",
  function() orbit_cycle("previous") end,
  { repeating = true }
)

o.bind("SUPER + Q", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("SUPER + Q", "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind("SUPER + SHIFT + Q", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind("SUPER + SHIFT + Q", "Reveal active window on top", hl.dsp.window.bring_to_top())

-- Replace Omarchy's mode shortcuts with the enabled Orbit policy.
hl.unbind("SUPER + T")
hl.unbind("SUPER + F")
hl.unbind("SUPER + CTRL + F")
hl.unbind("SUPER + ALT + F")

if window_modes.tiled and window_modes.floating then
  o.bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
elseif window_modes.tiled then
  o.bind("SUPER + T", "Tile window", hl.dsp.window.float({ action = "unset" }))
elseif window_modes.floating then
  o.bind("SUPER + T", "Float window", hl.dsp.window.float({ action = "set" }))
end
if window_modes.fullscreen then
  o.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
end
if window_modes.tiled_fullscreen then
  o.bind("SUPER + CTRL + F", "Tiled full screen", "omarchy-hyprland-window-tiled-fullscreen-toggle")
end
if window_modes.maximized then
  o.bind("SUPER + ALT + F", "Maximized", hl.dsp.window.fullscreen({ mode = "maximized" }))
end

o.bind("SUPER + Z", "Orbit snap layouts", hl.dsp.global("omarchy-window-switcher:snap"))
o.bind("SUPER + SHIFT + Z", "Orbit window modes", hl.dsp.global("omarchy-window-switcher:settings"))
