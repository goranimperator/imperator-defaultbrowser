#!/usr/bin/env node
// Resources/AppIcon.icns is the artwork itself and the only source of truth for
// it. This checks that it is a complete icon set rather than one size padded out,
// and that Resources/AppIcon.png, the preview the README shows, was actually cut
// from the current .icns rather than left behind by an earlier one.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync, readFileSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const icns = path.join(repoRoot, "Resources", "AppIcon.icns");
const preview = path.join(repoRoot, "Resources", "AppIcon.png");

/// Every representation macOS wants, and the pixel size each one has to be. A
/// stub built from a single image passes a name check but fails on the sizes.
const REQUIRED = {
  "icon_16x16.png": 16,
  "icon_16x16@2x.png": 32,
  "icon_32x32.png": 32,
  "icon_32x32@2x.png": 64,
  "icon_128x128.png": 128,
  "icon_128x128@2x.png": 256,
  "icon_256x256.png": 256,
  "icon_256x256@2x.png": 512,
  "icon_512x512.png": 512,
  "icon_512x512@2x.png": 1024,
};

const work = mkdtempSync(path.join(tmpdir(), "imperator-icon-check-"));
const failures = [];

function sipsProperty(file, key) {
  const out = execFileSync("/usr/bin/sips", ["-g", key, file], { encoding: "utf8" });
  return out.match(new RegExp(`${key}:\\s*(\\S+)`))?.[1] ?? "";
}

function md5(file) {
  return createHash("md5").update(readFileSync(file)).digest("hex");
}

try {
  const iconset = path.join(work, "AppIcon.iconset");
  execFileSync("/usr/bin/iconutil", ["-c", "iconset", "-o", iconset, icns], { stdio: "pipe" });

  const present = new Set(readdirSync(iconset));
  for (const [name, size] of Object.entries(REQUIRED)) {
    if (!present.has(name)) {
      failures.push(`missing representation ${name}`);
      continue;
    }
    const file = path.join(iconset, name);
    const width = Number(sipsProperty(file, "pixelWidth"));
    const height = Number(sipsProperty(file, "pixelHeight"));
    if (width !== size || height !== size) {
      failures.push(`${name} is ${width}x${height}, expected ${size}x${size}`);
    }
  }

  // macOS app icons sit on a transparent margin, so the artwork has to carry an
  // alpha channel. A flattened export would fill the corners with white.
  const largest = path.join(iconset, "icon_512x512@2x.png");
  if (present.has("icon_512x512@2x.png") && sipsProperty(largest, "hasAlpha") !== "yes") {
    failures.push("the 1024px representation has no alpha channel");
  }

  // The README preview has to match the current artwork. `sips` is deterministic
  // for a given input, so re-cutting it and comparing hashes catches a .icns that
  // was replaced without the preview being regenerated (make icon).
  if (!existsSync(preview)) {
    failures.push("Resources/AppIcon.png is missing");
  } else if (present.has("icon_256x256.png")) {
    const expected = path.join(work, "expected-preview.png");
    execFileSync(
      "/usr/bin/sips",
      ["-s", "format", "png", "-z", "128", "128", path.join(iconset, "icon_256x256.png"), "--out", expected],
      { stdio: "pipe" }
    );

    if (md5(preview) !== md5(expected)) {
      failures.push("Resources/AppIcon.png was not cut from the current .icns -- run make icon");
    }

    // Control for that comparison: a different size must hash differently, or the
    // check above would pass on any PNG at all.
    const wrongSize = path.join(work, "wrong-size.png");
    execFileSync(
      "/usr/bin/sips",
      ["-s", "format", "png", "-z", "64", "64", path.join(iconset, "icon_256x256.png"), "--out", wrongSize],
      { stdio: "pipe" }
    );
    if (md5(wrongSize) === md5(expected)) {
      failures.push("control failed: the preview comparison cannot tell two different images apart");
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

console.log(
  `${Object.keys(REQUIRED).length} representations at their declared sizes, README preview cut from the same .icns`
);
console.log("ICON_OK");
