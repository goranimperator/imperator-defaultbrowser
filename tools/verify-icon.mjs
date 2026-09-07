#!/usr/bin/env node
// Checks Resources/AppIcon.icns is a complete icon set, not a single-size stub.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const icns = path.join(repoRoot, "Resources", "AppIcon.icns");

const REQUIRED = [
  "icon_16x16.png",
  "icon_16x16@2x.png",
  "icon_32x32.png",
  "icon_32x32@2x.png",
  "icon_128x128.png",
  "icon_128x128@2x.png",
  "icon_256x256.png",
  "icon_256x256@2x.png",
  "icon_512x512.png",
  "icon_512x512@2x.png",
];

const work = mkdtempSync(path.join(tmpdir(), "imperator-icon-check-"));
const failures = [];

try {
  const iconset = path.join(work, "AppIcon.iconset");
  execFileSync("/usr/bin/iconutil", ["-c", "iconset", "-o", iconset, icns], { stdio: "pipe" });

  const present = new Set(readdirSync(iconset));
  for (const name of REQUIRED) {
    if (!present.has(name)) failures.push(`missing representation ${name}`);
  }

  const largest = path.join(iconset, "icon_512x512@2x.png");
  if (present.has("icon_512x512@2x.png")) {
    const dims = execFileSync("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", largest], {
      encoding: "utf8",
    });
    const width = Number(dims.match(/pixelWidth:\s*(\d+)/)?.[1] ?? 0);
    const height = Number(dims.match(/pixelHeight:\s*(\d+)/)?.[1] ?? 0);
    if (width !== 1024 || height !== 1024) {
      failures.push(`largest representation is ${width}x${height}, expected 1024x1024`);
    }
  }
} catch (error) {
  failures.push(`could not read ${path.relative(repoRoot, icns)}: ${error.message}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`${REQUIRED.length} representations present, largest is 1024x1024`);
console.log("ICON_OK");
