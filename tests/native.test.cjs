const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const test = require("node:test");

test("compositor gesture lifecycle rejects non-moves and handles release/cancel/close", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-drag-test-"));
  try {
    const binary = path.join(dir, "drag-tracker");
    execFileSync("c++", ["-std=c++20", "-Wall", "-Wextra", "-Werror", path.join(__dirname, "drag-tracker.cpp"), "-o", binary]);
    execFileSync(binary);
  } finally { fs.rmSync(dir, { recursive: true }); }
});
