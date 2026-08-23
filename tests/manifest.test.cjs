const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));

test("manifest declares a persistent overlay", () => {
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.id, "io.github.rohan-patnaik.window-switcher");
  assert.equal(manifest.name, "Orbit");
  assert.equal(manifest.version, "0.1.0");
  assert.deepEqual(manifest.kinds, ["overlay"]);
  assert.equal(manifest.keepLoaded, true);
  assert.equal(manifest.entryPoints.overlay, "Overlay.qml");
});

test("all entry points exist inside the repository", () => {
  for (const relativePath of Object.values(manifest.entryPoints)) {
    assert.equal(path.isAbsolute(relativePath), false);
    assert.equal(relativePath.split(path.sep).includes(".."), false);
    assert.equal(fs.existsSync(path.join(root, relativePath)), true);
  }
});

test("repository contains no internal symbolic links", () => {
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop();
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.name === ".git") continue;
      const entryPath = path.join(directory, entry.name);
      assert.equal(fs.lstatSync(entryPath).isSymbolicLink(), false, entryPath);
      if (entry.isDirectory()) pending.push(entryPath);
    }
  }
});
