#!/usr/bin/env node
// Checks that browser discovery returns real installed browsers and drops the
// throwaway ones LaunchServices registers from tool caches.
//
// The unfiltered handler list from `--list-handlers-raw` is the positive control:
// the assertion "no cache paths in the filtered list" only means something if the
// raw list actually contains cache paths for this machine to filter out.

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

// Positive control for the negative assertion above.
const rawCachePaths = rawPaths.filter((p) => CACHE_MARKERS.some((m) => p.includes(m)));
if (rawCachePaths.length === 0) {
  failures.push(
    "control failed: the unfiltered handler list has no cache paths on this machine, " +
      "so 'no cache paths after filtering' proves nothing"
  );
} else if (rawPaths.length <= rows.length) {
  failures.push(
    `control failed: filtering dropped nothing (raw ${rawPaths.length}, filtered ${rows.length})`
  );
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`filtered ${rawPaths.length} handlers down to ${rows.length} browsers:`);
for (const row of rows) {
  console.log(`  ${row.marker === "*" ? "default" : "       "} ${row.name} (${row.bundleID})`);
}
console.log(`control: dropped ${rawCachePaths.length} cached throwaway browser(s)`);
console.log("DISCOVERY_OK");
