#!/usr/bin/env node
// Launch smoke test: the signed bundle starts, stays up, and shuts down cleanly.
//
// The status bar item and the popover itself are covered by the manual UI gate --
// nothing here can see them without Accessibility permission, and a check that
// silently degrades to "passed" would be worse than an honest manual gate.

import { spawn, execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const bundle = path.join(repoRoot, "build", "Imperator DefaultBrowser.app");
const binary = path.join(bundle, "Contents", "MacOS", "DefaultBrowser");

if (!existsSync(binary)) {
  console.error(`FAIL no built bundle at ${bundle}; run make build first`);
  process.exit(1);
}

// Never fight an instance the user is running.
try {
  execFileSync("/usr/bin/pgrep", ["-x", "DefaultBrowser"], { stdio: "ignore" });
  console.error("FAIL an Imperator DefaultBrowser instance is already running; quit it first");
  process.exit(1);
} catch {
  // pgrep exits non-zero when nothing matches, which is what we want.
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const child = spawn(binary, [], { stdio: ["ignore", "pipe", "pipe"] });
let stderr = "";
child.stderr.on("data", (chunk) => (stderr += chunk));

let exitedEarly = null;
child.on("exit", (code, signal) => {
  exitedEarly = exitedEarly ?? { code, signal };
});

await sleep(3000);

if (exitedEarly) {
  console.error(
    `FAIL app exited on its own (code ${exitedEarly.code}, signal ${exitedEarly.signal})` +
      (stderr.trim() ? `\n${stderr.trim()}` : "")
  );
  process.exit(1);
}

const stopped = new Promise((resolve) => child.once("exit", (code, signal) => resolve({ code, signal })));
child.kill("SIGTERM");
const result = await Promise.race([stopped, sleep(5000).then(() => "timeout")]);

if (result === "timeout") {
  child.kill("SIGKILL");
  console.error("FAIL app did not exit within 5s of SIGTERM");
  process.exit(1);
}

if (stderr.trim()) {
  console.error(`FAIL app wrote to stderr while running:\n${stderr.trim()}`);
  process.exit(1);
}

console.log(`app stayed up for 3s and exited on SIGTERM (signal ${result.signal ?? "none"})`);
console.log("LAUNCH_OK");
