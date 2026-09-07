#!/usr/bin/env node
// Checks the browser ordering rules:
//   - with no saved order, the list is alphabetical by name
//   - a saved order is honoured, and browsers missing from it land at the end
//
// The saved order file is swapped out and restored around the run, so this does
// not disturb whatever order the user has set.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const binary = path.join(repoRoot, ".build", "release", "DefaultBrowser");
const orderDir = path.join(
  process.env.HOME ?? "",
  "Library/Application Support/ImperatorDefaultBrowser"
);
const orderFile = path.join(orderDir, "order.json");
const backupFile = path.join(orderDir, "order.json.verify-backup");

function names() {
  return execFileSync(binary, ["--list-browsers"], { encoding: "utf8" })
    .split("\n")
    .filter(Boolean)
    .map((line) => line.split("\t"))
    .map((fields) => ({ bundleID: fields[1], name: fields[2] }));
}

const failures = [];
let restored = false;

mkdirSync(orderDir, { recursive: true });
if (existsSync(orderFile)) {
  renameSync(orderFile, backupFile);
  restored = true;
}

try {
  // No saved order: alphabetical.
  const defaultOrder = names();
  if (defaultOrder.length < 2) {
    failures.push(`need at least two browsers to test ordering, found ${defaultOrder.length}`);
  }
  const alphabetical = [...defaultOrder].sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
  );
  if (defaultOrder.map((b) => b.name).join("|") !== alphabetical.map((b) => b.name).join("|")) {
    failures.push(
      `default order is not alphabetical: ${defaultOrder.map((b) => b.name).join(", ")}`
    );
  }

  // Saved order: honoured, with unlisted browsers pushed to the end.
  const reversed = [...defaultOrder].reverse();
  const saved = reversed.slice(0, reversed.length - 1).map((b) => b.bundleID);
  const omitted = reversed[reversed.length - 1];
  writeFileSync(orderFile, JSON.stringify(saved));

  const custom = names();
  const expected = [...saved, omitted.bundleID];
  if (custom.map((b) => b.bundleID).join("|") !== expected.join("|")) {
    failures.push(
      `saved order not honoured. expected ${expected.join(", ")}, got ${custom
        .map((b) => b.bundleID)
        .join(", ")}`
    );
  }

  // Control: the saved order has to actually differ from alphabetical, otherwise
  // "saved order honoured" would pass without the saved order doing anything.
  if (expected.join("|") === alphabetical.map((b) => b.bundleID).join("|")) {
    failures.push("control failed: the test order is identical to the alphabetical order");
  }
} finally {
  rmSync(orderFile, { force: true });
  if (restored) renameSync(backupFile, orderFile);
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log("default order alphabetical, saved order honoured, unlisted browsers last");
console.log("ORDER_OK");
