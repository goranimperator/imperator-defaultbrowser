#!/usr/bin/env node
// The app is on Swift 6 language mode with Observation, and stays there.
//
// Both halves are easy to give up under pressure: a new concurrency diagnostic
// is quickest to silence by dropping the manifest back to .v5, and a store is
// quickest to wire up the old way. Each of those is a one-line edit that no
// diff reader would flag, so both are pinned here.

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");

function read(relative) {
  const file = path.join(repoRoot, relative);
  return existsSync(file) ? readFileSync(file, "utf8") : "";
}

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
}

function swiftFiles(dir) {
  const found = [];
  for (const entry of readdirSync(dir)) {
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) found.push(...swiftFiles(full));
    else if (entry.endsWith(".swift")) found.push(full);
  }
  return found;
}

const failures = [];
function require(condition, message) {
  if (!condition) failures.push(message);
}

// 1. Swift 6 language mode in the manifest.
const manifest = read("Package.swift");
require(
  stripComments(manifest).includes(".swiftLanguageMode(.v6)"),
  "the target is not built in Swift 6 language mode"
);
require(
  !stripComments(manifest).includes(".swiftLanguageMode(.v5)"),
  "the target has been dropped back to Swift 5 language mode"
);

// The deployment target is a promise in the README, not a knob to turn when a
// macOS 27 API looks convenient.
require(
  manifest.includes(".macOS(.v14)"),
  "the deployment target is no longer macOS 14"
);

// 2. Observation, not ObservableObject.
const sources = new Map(
  swiftFiles(path.join(repoRoot, "Sources")).map((file) => [
    path.relative(repoRoot, file),
    readFileSync(file, "utf8"),
  ])
);

const store = sources.get("Sources/DefaultBrowser/Services/BrowserStore.swift") ?? "";
require(store.length > 0, "BrowserStore.swift is missing");
require(
  stripComments(store).includes("@Observable"),
  "BrowserStore is not an Observation type"
);

for (const [legacy, label] of [
  [": ObservableObject", "ObservableObject conformance"],
  ["@Published", "@Published"],
  ["@EnvironmentObject", "@EnvironmentObject"],
  [".environmentObject(", ".environmentObject("],
  ["@StateObject", "@StateObject"],
  ["@ObservedObject", "@ObservedObject"],
]) {
  const offenders = [...sources.entries()]
    .filter(([, text]) => stripComments(text).includes(legacy))
    .map(([file]) => file);
  require(
    offenders.length === 0,
    `${label} is back in ${offenders.join(", ")}: Observation replaced it`
  );
}

// Views read the store through the Observation environment.
require(
  stripComments(sources.get("Sources/DefaultBrowser/Views/PopoverContentView.swift") ?? "")
    .includes("@Environment(BrowserStore.self)"),
  "PopoverContentView does not read the store from the Observation environment"
);
require(
  stripComments(sources.get("Sources/DefaultBrowser/Views/SettingsView.swift") ?? "")
    .includes("@Environment(BrowserStore.self)"),
  "SettingsView does not read the store from the Observation environment"
);

// 3. Structured concurrency for the confirmation poll. The DispatchWorkItem it
// replaced rescheduled itself, so the deadline, the give-up message and the
// cancellation were spread across three closures.
require(
  !stripComments(store).includes("DispatchWorkItem"),
  "the confirmation poll is back on a self-rescheduling DispatchWorkItem"
);
require(
  stripComments(store).includes("Task.sleep(for: .seconds(Self.confirmationInterval))"),
  "the confirmation poll does not sleep between reads"
);
require(
  stripComments(store).includes("confirmationTask?.cancel()"),
  "a second switch does not cancel the first switch's confirmation poll"
);

// The generous window is a measured value, not a guess: an earlier 9.6s window
// gave up on switches that had in fact landed and showed a false failure.
require(
  /confirmationWindow: TimeInterval = 60\b/.test(store),
  "the confirmation window is no longer 60 seconds"
);

// Controls: each negative assertion above has to fire on the shape it forbids.
if (stripComments("// @Published var x").includes("@Published")) {
  failures.push("control failed: stripComments does not remove line comments");
}
if (!stripComments("@Published var x = 1").includes("@Published")) {
  failures.push("control failed: stripComments eats real code");
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(
  `Swift 6 language mode on a macOS 14 minimum, ${sources.size} Swift files free of ObservableObject, store confirmed by a cancellable Task`
);
console.log("MODERN_OK");
