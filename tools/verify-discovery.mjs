#!/usr/bin/env node
// Checks that browser discovery returns real installed browsers and drops the
// throwaway ones LaunchServices registers from outside the application folders.
//
// The unfiltered handler list from `--list-handlers-raw` is the positive control:
// the assertion "nothing outside an application root survived" only means
// something if the raw list actually holds such a handler for this machine to
// filter out. The control is stated against the application roots, not against a
// list of known cache markers, because the roots are what BrowserService filters
// on. A marker list goes stale the moment a tool ships its browser somewhere new:
// Playwright uses ~/Library/Caches, Screaming Frog uses ~/.ScreamingFrogSEOSpider,
// and the next one will pick a third place. Both get dropped for the same reason.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const binary = path.join(repoRoot, ".build", "release", "DefaultBrowser");

const CACHE_MARKERS = ["/Caches/", "/.cache/", "ms-playwright", "puppeteer", "/selenium"];

const ALLOWED_ROOTS = [
  "/Applications",
  "/System/Applications",
  "/System/Library/CoreServices",
  "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
  path.join(process.env.HOME ?? "", "Applications"),
];

function run(flag) {
  return execFileSync(binary, [flag], { encoding: "utf8" })
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

const failures = [];

const rawPaths = run("--list-handlers-raw");
const rows = run("--list-browsers").map((line) => {
  const [marker, bundleID, name, appPath] = line.split("\t");
  return { marker, bundleID, name, appPath };
});

if (rows.length === 0) {
  failures.push("no browsers discovered at all");
}

for (const row of rows) {
  if (!row.bundleID || !row.name || !row.appPath) {
    failures.push(`malformed record: ${JSON.stringify(row)}`);
    continue;
  }
  if (!ALLOWED_ROOTS.some((root) => row.appPath === root || row.appPath.startsWith(root + "/"))) {
    failures.push(`${row.name} sits outside every application root: ${row.appPath}`);
  }
  for (const marker of CACHE_MARKERS) {
    if (row.appPath.includes(marker)) {
      failures.push(`${row.name} is a cached throwaway browser: ${row.appPath}`);
    }
  }
}

const defaults = rows.filter((row) => row.marker === "*");
if (defaults.length !== 1) {
  failures.push(`expected exactly one browser marked default, found ${defaults.length}`);
}

// Positive control for the negative assertions above.
//
// Whether this machine has anything to filter is not something the app
// controls, and a gate that fails because the user uninstalled Screaming Frog
// is reporting on the machine rather than on the code. So: exercise the control
// when a real outsider is present, and otherwise require that the same rule is
// covered deterministically in SelfTest, which runs the actual filter against
// fixed paths and is gated by G11. The negative assertion above is checked
// either way; this decides whether it was exercised here or delegated.
const outsiders = rawPaths.filter(
  (p) => !ALLOWED_ROOTS.some((root) => p === root || p.startsWith(root + "/"))
);

let controlNote;
if (outsiders.length > 0) {
  if (rawPaths.length <= rows.length) {
    failures.push(
      `control failed: an out-of-root handler is present but filtering dropped nothing (raw ${rawPaths.length}, filtered ${rows.length})`
    );
  }
  for (const outsider of outsiders) {
    if (rows.some((row) => row.appPath === outsider)) {
      failures.push(`${outsider} survived filtering but sits outside every application root`);
    }
  }
  controlNote =
    `control exercised on this machine: dropped ${outsiders.length} handler(s) outside every application root:\n` +
    outsiders.map((o) => `  ${o}`).join("\n");
} else {
  // Nothing to filter here. Delegate, and prove the delegate exists.
  const selfTest = readFileSync(
    path.join(repoRoot, "Sources", "DefaultBrowser", "Services", "SelfTest.swift"),
    "utf8"
  );
  const required = [
    "ms-playwright",
    "puppeteer",
    ".ScreamingFrogSEOSpider",
    "/ApplicationsEvil/",
  ];
  const missing = required.filter((marker) => !selfTest.includes(marker));
  if (missing.length > 0) {
    failures.push(
      "control failed: this machine has no out-of-root handler to filter, and " +
        `SelfTest no longer covers the rule either (missing: ${missing.join(", ")})`
    );
  }
  if (!selfTest.includes("!BrowserService.isInApplicationDirectory(")) {
    failures.push(
      "control failed: SelfTest has no negative isInApplicationDirectory assertion to stand in for the missing machine control"
    );
  }
  controlNote =
    "control delegated: every handler on this machine already sits in an application root, " +
    `so the rule is covered by SelfTest's fixed-path assertions instead (G11, ${required.length} out-of-root cases)`;
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`filtered ${rawPaths.length} handlers down to ${rows.length} browsers:`);
for (const row of rows) {
  console.log(`  ${row.marker === "*" ? "default" : "       "} ${row.name} (${row.bundleID})`);
}
console.log(controlNote);
console.log("DISCOVERY_OK");
