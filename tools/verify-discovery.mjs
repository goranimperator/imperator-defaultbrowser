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
const outsiders = rawPaths.filter(
  (p) => !ALLOWED_ROOTS.some((root) => p === root || p.startsWith(root + "/"))
);
if (outsiders.length === 0) {
  failures.push(
    "control failed: every handler LaunchServices reports already sits in an application " +
      "root on this machine, so 'nothing outside a root survived' proves nothing. Install " +
      "a tool that unpacks its own browser (Playwright, Puppeteer, Screaming Frog) and rerun"
  );
} else if (rawPaths.length <= rows.length) {
  failures.push(
    `control failed: filtering dropped nothing (raw ${rawPaths.length}, filtered ${rows.length})`
  );
} else {
  for (const outsider of outsiders) {
    if (rows.some((row) => row.appPath === outsider)) {
      failures.push(`${outsider} survived filtering but sits outside every application root`);
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`filtered ${rawPaths.length} handlers down to ${rows.length} browsers:`);
for (const row of rows) {
  console.log(`  ${row.marker === "*" ? "default" : "       "} ${row.name} (${row.bundleID})`);
}
console.log(`control: dropped ${outsiders.length} handler(s) outside every application root:`);
for (const outsider of outsiders) console.log(`  ${outsider}`);
console.log("DISCOVERY_OK");
