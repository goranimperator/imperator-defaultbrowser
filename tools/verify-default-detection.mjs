#!/usr/bin/env node
// Checks that the browser the app reports as default is the browser macOS has
// actually registered as the https handler.
//
// The app reads this through NSWorkspace. This script reads it from the
// LaunchServices preference plist instead, so agreement is two independent
// measurements rather than one API echoing itself.

import { execFileSync } from "node:child_process";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const binary = path.join(repoRoot, ".build", "release", "DefaultBrowser");
const plist = path.join(
  process.env.HOME ?? "",
  "Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
);

const reported = execFileSync(binary, ["--list-browsers"], { encoding: "utf8" })
  .split("\n")
  .map((line) => line.split("\t"))
  .filter((fields) => fields[0] === "*")
  .map((fields) => fields[1]);

if (reported.length !== 1) {
  console.error(`FAIL app reported ${reported.length} default browsers, expected 1`);
  process.exit(1);
}

const dump = execFileSync("/usr/bin/plutil", ["-p", plist], { encoding: "utf8" });

// Each LSHandlers entry is a block of "key" => value lines. Find the block whose
// LSHandlerURLScheme is https and read its role handler out of the same block.
//
// LSHandlerPreferredVersions is a nested dict that reuses the LSHandlerRoleAll key
// for a version string, so it has to be stripped before matching the handler.
const blocks = dump.split(/\n\s*\d+ => \{/);
let oracle = null;
for (const rawBlock of blocks) {
  if (!/"LSHandlerURLScheme"\s*=>\s*"https"/.test(rawBlock)) continue;
  const block = rawBlock.replace(/"LSHandlerPreferredVersions"\s*=>\s*\{[^}]*\}/g, "");
  const role = block.match(/"LSHandlerRole(?:All|Viewer)"\s*=>\s*"([^"]+)"/);
  if (role) {
    oracle = role[1];
    break;
  }
}

if (!oracle) {
  console.error("FAIL no https handler found in the LaunchServices plist");
  process.exit(1);
}

if (oracle.toLowerCase() !== reported[0].toLowerCase()) {
  console.error(`FAIL app reports "${reported[0]}", LaunchServices plist says "${oracle}"`);
  process.exit(1);
}

console.log(`app and LaunchServices plist agree: ${reported[0]}`);
console.log("DEFAULT_DETECTION_OK");
