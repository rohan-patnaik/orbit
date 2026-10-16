const assert = require("node:assert/strict");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const test = require("node:test");

function configured(tsv = "", nativeBridge = false, scenario = "", rescueInstalled = false) {
  const lua = `
    local config = ${JSON.stringify(tsv)}
    io.popen = function() return { read=function() return config end, close=function() end } end
    local function dispatcher(name)
      return setmetatable({}, {
        __index=function(_, key) return dispatcher(name .. "." .. key) end,
        __call=function(_, args) return {name=name, args=args or {}} end
      })
    end
    hl = {dsp=dispatcher("hl.dsp"), unbind=function(key) print("unbind\\t" .. key) end,
      layer_rule=function(rule) print("layer\\t" .. rule.match.namespace .. "\\t" .. tostring(rule.no_anim) .. "\\t" .. rule.animation) end,
      dispatch=function(action)
        local args = action.args
        if type(args) == "table" then
          args = action.name .. " " .. tostring(args.window or args.key or "") .. " " .. tostring(args.workspace or args.mode or args.state or "")
        end
        print("dispatch\\t" .. args)
      end,
      on=function(event, callback)
        print("on\\t" .. event)
        orbit_test_handlers = orbit_test_handlers or {}
        orbit_test_handlers[event] = callback
        return {is_active=function() return true end, remove=function() end}
      end,
      timer=function(callback, options) print("timer\\t" .. options.timeout); callback(); return {} end,
      get_windows=function() return orbit_test_windows or {} end,
      get_active_workspace=function() return {id=5, name="5"} end,
      get_active_window=function() return orbit_test_active end}
    local real_open = io.open
    io.open = function(file, mode)
      if file == "/usr/local/lib/orbit-rescue/orbit_rescue.py" then
        return ${rescueInstalled} and {close=function() end} or nil
      end
      return real_open(file, mode)
    end
    if ${nativeBridge} then
      hl.plugin = {orbit={
        next=function() print("native\\tnext") end,
        previous=function() print("native\\tprevious") end
      }}
    end
    o = {
      shell_quote=function(s) return s end,
      bind=function(key, label, action)
        if type(action) == "function" then
          print("bind\\t" .. key .. "\\t" .. label .. "\\tcallback")
          action()
          -- The same callback must survive the bridge being unloaded.
          if hl.plugin then hl.plugin=nil; action() end
          return
        end
        print("bind\\t" .. key .. "\\t" .. label .. "\\t" .. (type(action) == "table" and action.name or action) .. "\\t" .. (type(action) == "table" and (action.args.action or "") or ""))
      end,
      window=function(match, rules)
        for key, value in pairs(rules) do print("rule\\t" .. key .. "\\t" .. tostring(type(match) == "table" and match.float) .. "\\t" .. tostring(type(match) == "table" and match.class) .. "\\t" .. tostring(value)) end
      end
    }
    dofile(${JSON.stringify(path.join(__dirname, "..", "bindings.lua"))})
    print("scenario")
    ${scenario}
  `;
  return execFileSync("lua", ["-"], {input: lua, encoding: "utf8"}).trim().split("\n").map(line => line.split("\t"));
}
test("only the switcher and handoff bypass compositor fades", () => {
  const layers = configured().filter(row => row[0] === "layer");
  assert.deepEqual(layers, [["layer", "^(omarchy-window-switcher|omarchy-orbit-handoff)$", "true", "none"]]);
});
test("Alt+Tab owns forward/reverse shortcuts and unbinds existing ones", () => {
  const rows = configured();
  for (const key of ["ALT + TAB", "ALT + SHIFT + TAB"])
    assert.ok(rows.some(row => row[0] === "unbind" && row[1] === key));
  assert.ok(rows.some(row => row[0] === "bind" && row[1] === "ALT + TAB" && row[3] === "callback"));
  assert.ok(rows.some(row => row[0] === "dispatch" && row[1] === "omarchy-window-switcher:next"));
  assert.ok(rows.some(row => row[0] === "bind" && row[1] === "SUPER + SHIFT + Z"));
});
test("normal binding prefers ordered native events and falls back after bridge unload", () => {
  const rows = configured("", true);
  assert.ok(rows.some(row => row[0] === "native" && row[1] === "next"));
  assert.ok(rows.some(row => row[0] === "dispatch" && row[1] === "omarchy-window-switcher:next"));
});
test("default installation preserves tiling; personal maximized default excludes floating utilities", () => {
  assert.equal(configured().filter(row => row[0] === "rule" && row[2] === "false" && row[3] === ".*").length, 0);
  const personal = configured("maximized\ttrue\ttrue\ttrue\ttrue\ttrue");
  assert.ok(personal.some(row => row[0] === "rule" && row[1] === "maximize" && row[2] === "false"));
});
test("mode shortcuts honor disabled options and retain an escape to the sole normal mode", () => {
  const rows = configured("tiled\ttrue\tfalse\tfalse\tfalse\tfalse");
  const binds = rows.filter(row => row[0] === "bind");
  assert.equal(binds.some(row => row[1] === "SUPER + F"), false);
  assert.equal(binds.some(row => row[1] === "SUPER + ALT + F"), false);
  assert.ok(binds.some(row => row[1] === "SUPER + T" && row[4] === "disable"));
});
test("invalid all-disabled policy recovers a maximized launch mode", () => {
  const rows = configured("invalid\tfalse\tfalse\tfalse\tfalse\tfalse");
  assert.ok(rows.some(row => row[0] === "rule" && row[1] === "maximize"));
  assert.ok(rows.some(row => row[0] === "bind" && row[1] === "SUPER + ALT + F"));
});

test("Task Manager shortcut replaces any prior binding and leaves btop shortcut alone", () => {
  const rows = configured();
  assert.ok(rows.some(row => row[0] === "unbind" && row[1] === "CTRL + SHIFT + ESCAPE"));
  assert.ok(rows.some(row => row[0] === "bind" && row[1] === "CTRL + SHIFT + ESCAPE" && row[3].endsWith("/scripts/task-manager.py")));
  assert.equal(rows.some(row => row[1] === "SUPER + CTRL + T"), false);
});

test("Task Manager floating exception follows the ordinary maximized launch rule", () => {
  const rules = configured("maximized\ttrue\ttrue\ttrue\ttrue\ttrue").filter(r => r[0] === 'rule');
  const ordinary = rules.findIndex(r => r[1] === 'maximize' && r[3] === '.*');
  const utility = rules.findIndex(r => r[1] === 'maximize' && r[3] === '^[Xx]fce4-taskmanager$');
  assert.ok(ordinary >= 0 && utility > ordinary);
  assert.equal(rules[utility][4], 'false');
  assert.ok(rules.some(r => r[1] === 'float' && r[3] === '^[Xx]fce4-taskmanager$' && r[4] === 'true'));
});

const taskManager = (address, pid, workspace) =>
  `{address="${address}", pid=${pid}, class="xfce4-taskmanager", mapped=true, workspace={id=${workspace}, name="${workspace}"}}`;
const after = rows => rows.slice(rows.findIndex(row => row[0] === "scenario") + 1);

test("Task Manager and its dialogs open raised on the focused workspace despite a static workspace rule", () => {
  const rows = after(configured("", false, `
    local main = ${taskManager("0xa", 7, 1)}
    orbit_test_windows = {main}
    orbit_test_handlers["window.open"](main)
    print("dialog")
    main.workspace = {id=5, name="5"}
    local dialog = ${taskManager("0xb", 7, 1)}
    orbit_test_windows = {main, dialog}
    orbit_test_handlers["window.open"](dialog)
  `));
  const split = rows.findIndex(row => row[0] === "dialog");
  const mainRows = rows.slice(0, split).map(row => row[1]);
  const dialogRows = rows.slice(split + 1).map(row => row[1]);
  assert.deepEqual(mainRows, ["hl.dsp.window.move address:0xa 5", "hl.dsp.focus address:0xa ", "hl.dsp.window.alter_zorder address:0xa top"]);
  assert.deepEqual(dialogRows, ["hl.dsp.window.move address:0xb 5", "hl.dsp.focus address:0xb ", "hl.dsp.window.alter_zorder address:0xb top"]);
});

test("activating Task Manager keeps its open modal dialog in front until the dialog closes", () => {
  const rows = after(configured("", false, `
    local main = ${taskManager("0xa", 7, 5)}
    local dialog = ${taskManager("0xb", 7, 5)}
    local other = {address="0xc", pid=9, class="firefox", mapped=true, workspace={id=5, name="5"}}
    orbit_test_windows = {main}
    orbit_test_handlers["window.open"](main)
    orbit_test_windows = {main, dialog, other}
    orbit_test_handlers["window.open"](dialog)
    print("activate")
    orbit_test_handlers["window.active"](main)
    orbit_test_handlers["window.active"](dialog)
    orbit_test_handlers["window.active"](other)
    print("closed")
    orbit_test_handlers["window.close"](dialog)
    orbit_test_handlers["window.close"]({})
    orbit_test_handlers["window.active"](main)
  `));
  const activate = rows.findIndex(row => row[0] === "activate");
  const closed = rows.findIndex(row => row[0] === "closed");
  assert.deepEqual(rows.slice(activate + 1, closed).map(row => row.join(" ")),
    ["timer 50", "dispatch hl.dsp.focus address:0xb ", "dispatch hl.dsp.window.alter_zorder address:0xb top"]);
  assert.deepEqual(rows.slice(closed + 1), []);
});

test("Shift+F10 opens the Task Manager row menu without consuming the chord elsewhere", () => {
  const rows = after(configured("", false, `
    local handler
    o.bind = function(key, label, action, options)
      if key == "SHIFT + F10" then handler = action; print("options\\t" .. tostring(options and options.non_consuming)) end
    end
    dofile(${JSON.stringify(path.join(__dirname, "..", "bindings.lua"))})
    orbit_test_active = {address="0xc", class="firefox"}
    handler()
    print("taskmanager")
    orbit_test_active = ${taskManager("0xa", 7, 5)}
    handler()
  `));
  assert.ok(rows.some(row => row[0] === "options" && row[1] === "true"));
  const split = rows.findIndex(row => row[0] === "taskmanager");
  assert.equal(rows.slice(0, split).some(row => row[0] === "dispatch"), false);
  assert.deepEqual(rows.slice(split + 1).filter(row => row[0] === "dispatch").map(row => row[1]),
    ["hl.dsp.send_key_state Menu down", "hl.dsp.send_key_state Menu up"]);
});

test("rescue chords are swallowed only when the optional rescue service is installed", () => {
  const binds = rescue => configured("", false, "", rescue).filter(row => row[0] === "bind").map(row => row[1]);
  for (const chord of ["CTRL + ALT + SHIFT + ESCAPE", "SUPER + CTRL + SHIFT + B"]) {
    assert.equal(binds(false).includes(chord), false);
    assert.equal(binds(true).includes(chord), true);
  }
});
