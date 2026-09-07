#!/usr/bin/env node
// Runs the binary's own assertions over the pure logic: case-insensitive default
// matching, saved-order application, and the discovery filters.
//
// The assertions live in Sources/DefaultBrowser/Services/SelfTest.swift because
// they need the app's own types. This script only builds, runs them, and refuses
// to pass on a stale binary.

import { execFileSync } from "node:child_process";
import { existsSync, statSync, readdirSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const binary = path.join(repoRoot, ".build", "release", "DefaultBrowser");

function fail(message) {
  console.error(`FAIL ${message}`);
  process.exit(1);
}

execFileSync("swift", ["build", "-c", "release"], { cwd: repoRoot, stdio: "pipe" });

if (!existsSync(binary)) fail("release binary missing after swift build");

// A binary older than the sources it is meant to be testing would report on code
// that is no longer there.
function newestSourceTime(dir) {
  let newest = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) newest = Math.max(newest, newestSourceTime(full));
    else if (entry.name.endsWith(".swift")) newest = Math.max(newest, statSync(full).mtimeMs);
  }
  return newest;
}

const sourceTime = newestSourceTime(path.join(repoRoot, "Sources"));
if (statSync(binary).mtimeMs < sourceTime) fail("release binary is older than the Swift sources");

let output;
try {
  output = execFileSync(binary, ["--self-test"], { encoding: "utf8" });
} catch (error) {
  const combined = `${error.stdout ?? ""}${error.stderr ?? ""}`.trim();
  fail(`--self-test exited ${error.status}: ${combined || error.message}`);
}

if (!output.includes("SELFTEST_OK")) fail(`--self-test did not report success: ${output.trim()}`);

// Control for the whole harness: the flag has to be real. A binary that ignored
// it would launch the app instead of printing assertions, so an unknown flag
// must not produce the success marker.
let strayOutput = "";
try {
  strayOutput = execFileSync(binary, ["--list-handlers-raw"], { encoding: "utf8" });
} catch {
  strayOutput = "";
}
if (strayOutput.includes("SELFTEST_OK")) {
  fail("control failed: the success marker appears without --self-test");
}

const assertions = output.trim().split("\n").filter((line) => line !== "SELFTEST_OK");
console.log(assertions.join(" | "));
console.log("SELFTEST_OK");
