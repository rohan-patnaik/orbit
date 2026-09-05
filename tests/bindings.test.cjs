const assert = require("node:assert/strict");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const test = require("node:test");

function configured(tsv = "", nativeBridge = false) {
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
      dispatch=function(action) print("dispatch\\t" .. action.args) end}
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
        for key in pairs(rules) do print("rule\\t" .. key .. "\\t" .. tostring(type(match) == "table" and match.float)) end
      end
    }
    dofile(${JSON.stringify(path.join(__dirname, "..", "bindings.lua"))})
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
  assert.equal(configured().filter(row => row[0] === "rule").length, 0);
  const personal = configured("maximized\ttrue\ttrue\ttrue\ttrue\ttrue");
  assert.ok(personal.some(row => row[0] === "rule" && row[1] === "maximize" && row[2] === "false"));
});
test("mode shortcuts honor disabled options and retain an escape to the sole normal mode", () => {
  const rows = configured("tiled\ttrue\tfalse\tfalse\tfalse\tfalse");
  const binds = rows.filter(row => row[0] === "bind");
  assert.equal(binds.some(row => row[1] === "SUPER + F"), false);
  assert.equal(binds.some(row => row[1] === "SUPER + ALT + F"), false);
  assert.ok(binds.some(row => row[1] === "SUPER + T" && row[4] === "unset"));
});
test("invalid all-disabled policy recovers a maximized launch mode", () => {
  const rows = configured("invalid\tfalse\tfalse\tfalse\tfalse\tfalse");
  assert.ok(rows.some(row => row[0] === "rule" && row[1] === "maximize"));
  assert.ok(rows.some(row => row[0] === "bind" && row[1] === "SUPER + ALT + F"));
});
