-- Orbit replaces Omarchy's stock Alt+Tab bindings. Keep the original
-- window-cycle behavior available on Super+Q.
local orbit_plugin_id = "io.github.rohan-patnaik.window-switcher"

-- A compositor fade keeps the outgoing cover visible after the destination is
-- ready. These keyboard surfaces must map/unmap on the frame Orbit requests.
hl.layer_rule({
  match = { namespace = "^(omarchy-window-switcher|omarchy-orbit-handoff)$" },
  no_anim = true,
  animation = "none",
})

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

-- Task Manager is a movable utility, including when ordinary apps maximize.
-- Static launch rules leave later user moves/resizes/fullscreen choices intact.
o.window({ class = "^[Xx]fce4-taskmanager$", float = false }, {
  float = true,
  maximize = false,
  fullscreen = false,
  size = { "monitor_w * 0.6", "monitor_h * 0.7" },
  center = true,
})

-- Some configs pin every new window to one workspace (for example a static
-- `workspace = "1 silent"` rule). Task Manager and its confirmation dialogs
-- must still appear where the user is: beside an existing Task Manager window,
-- otherwise on the focused workspace, raised and focused so Enter/Esc work.
--
-- Its Settings and confirmation dialogs are modal, but GTK3 does not tell the
-- compositor, so clicking the main window would bury a dialog that still owns
-- input. Like Windows, keep the newest open dialog above its Task Manager.
local function orbit_is_task_manager(window)
  return window ~= nil and type(window.class) == "string"
    and window.class:lower() == "xfce4-taskmanager"
end

local function orbit_workspace_selector(workspace)
  if workspace == nil or workspace.special then
    return nil
  end
  if workspace.id and workspace.id > 0 then
    return tostring(workspace.id)
  end
  return "name:" .. workspace.name
end

orbit_task_manager_dialogs = orbit_task_manager_dialogs or {}
orbit_task_manager_dialog_serial = orbit_task_manager_dialog_serial or 0

local function orbit_raise(window)
  local address = "address:" .. window.address
  hl.dispatch(hl.dsp.focus({ window = address }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = address }))
end

function orbit_place_task_manager(window)
  if not orbit_is_task_manager(window) then
    return
  end
  local target = nil
  for _, other in ipairs(hl.get_windows()) do
    if other.address ~= window.address and other.pid == window.pid
      and other.mapped and orbit_is_task_manager(other) then
      target = other.workspace
      break
    end
  end
  if target then
    orbit_task_manager_dialog_serial = orbit_task_manager_dialog_serial + 1
    orbit_task_manager_dialogs[window.address] = orbit_task_manager_dialog_serial
  end
  target = target or hl.get_active_workspace()
  local selector = orbit_workspace_selector(target)
  if selector and (window.workspace == nil or window.workspace.id ~= target.id) then
    hl.dispatch(hl.dsp.window.move({
      workspace = selector, follow = false, window = "address:" .. window.address,
    }))
  end
  orbit_raise(window)
end

function orbit_keep_task_manager_dialog_on_top(window)
  if not orbit_is_task_manager(window) or orbit_task_manager_dialogs[window.address] then
    return
  end
  local dialog, newest = nil, 0
  for _, other in ipairs(hl.get_windows()) do
    local serial = orbit_task_manager_dialogs[other.address]
    if serial and serial > newest and other.pid == window.pid and other.mapped then
      dialog, newest = other, serial
    end
  end
  if dialog == nil then
    return
  end
  -- Raise after the click that activated the main window has been handled;
  -- focusing synchronously here is undone by that same click.
  local address = dialog.address
  orbit_task_manager_raise_timer = hl.timer(function()
    for _, other in ipairs(hl.get_windows()) do
      if other.address == address and other.mapped and orbit_task_manager_dialogs[address] then
        orbit_raise(other)
        return
      end
    end
  end, { timeout = 50, type = "oneshot" })
end

function orbit_forget_task_manager_dialog(window)
  if window ~= nil and window.address ~= nil then
    orbit_task_manager_dialogs[window.address] = nil
  end
end

for _, subscription in ipairs(orbit_task_manager_subscriptions or {}) do
  if subscription:is_active() then
    subscription:remove()
  end
end
if orbit_task_manager_subscription and orbit_task_manager_subscription:is_active() then
  orbit_task_manager_subscription:remove()
end
orbit_task_manager_subscription = nil
orbit_task_manager_subscriptions = {
  hl.on("window.open", orbit_place_task_manager),
  hl.on("window.active", orbit_keep_task_manager_dialog_on_top),
  hl.on("window.close", orbit_forget_task_manager_dialog),
}

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
  o.bind("SUPER + T", "Tile window", hl.dsp.window.float({ action = "disable" }))
elseif window_modes.floating then
  o.bind("SUPER + T", "Float window", hl.dsp.window.float({ action = "enable" }))
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

-- Read Orbit's feature preference at launch time; off/missing GUI uses btop.
hl.unbind("CTRL + SHIFT + ESCAPE")
o.bind("CTRL + SHIFT + ESCAPE", "Task Manager", "python3 " .. o.shell_quote(
  (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config"))
    .. "/omarchy/plugins/" .. orbit_plugin_id .. "/scripts/task-manager.py"
))

-- Windows opens a list's context menu with Shift+F10 as well as the Menu key.
-- Xfce Task Manager only listens for Menu, so add it there without consuming
-- Shift+F10 for any other app.
hl.unbind("SHIFT + F10")
o.bind("SHIFT + F10", "Task Manager row menu", function()
  if not orbit_is_task_manager(hl.get_active_window()) then
    return
  end
  hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Menu", state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Menu", state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end, { non_consuming = true })

-- Orbit's optional rescue service (rescue/install.sh) reads these chords below
-- the compositor so they work even when it is frozen. While Hyprland is alive,
-- keep them from also reaching the focused app.
local orbit_rescue_module = io.open("/usr/local/lib/orbit-rescue/orbit_rescue.py", "r")
if orbit_rescue_module then
  orbit_rescue_module:close()
  hl.unbind("CTRL + ALT + SHIFT + ESCAPE")
  o.bind("CTRL + ALT + SHIFT + ESCAPE", "Rescue screen", function() end)
  hl.unbind("SUPER + CTRL + SHIFT + B")
  o.bind("SUPER + CTRL + SHIFT + B", "Restart graphics", function() end)
end
