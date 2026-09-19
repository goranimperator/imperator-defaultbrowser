#!/usr/bin/env node
// AppKit picks which generation of controls to draw from the sdk field in the
// binary's LC_BUILD_VERSION, not from the macOS it runs on. SwiftPM stamps that
// field with the deployment target, so a build pinned to macOS 14 would draw
// macOS 14 era controls forever: a narrow switch with a round knob instead of
// the wide capsule macOS 27 draws.
//
// The Makefile passes -platform_version to the linker so the binary reports the
// real SDK while keeping the low minimum. This checks the shipped binary really
// carries both halves of that, because the symptom of losing it is purely
// visual and would ship unnoticed.

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const bundleBinary = path.join(
  repoRoot,
  "build",
  "Imperator DefaultBrowser.app",
  "Contents",
  "MacOS",
  "DefaultBrowser"
);

const MIN_EXPECTED = "14.0";

const failures = [];

function fail(message) {
  failures.push(message);
}

/** The minos and sdk fields out of LC_BUILD_VERSION, as strings. */
function buildVersion(binary) {
  const out = execFileSync("/usr/bin/otool", ["-l", binary], { encoding: "utf8" });
  const block = out.split("LC_BUILD_VERSION")[1] ?? "";
  return {
    minos: block.match(/\bminos\s+([\d.]+)/)?.[1] ?? "",
    sdk: block.match(/\bsdk\s+([\d.]+)/)?.[1] ?? "",
  };
}

try {
  execFileSync("make", ["build"], { cwd: repoRoot, stdio: "pipe" });
} catch (error) {
  fail(`make build failed: ${error.message}`);
}

const sdkInstalled = execFileSync("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"], {
  encoding: "utf8",
}).trim();

if (!existsSync(bundleBinary)) {
  fail("no binary in the built bundle");
} else {
  const { minos, sdk } = buildVersion(bundleBinary);

  if (minos !== MIN_EXPECTED) {
    fail(`bundle reports minos ${minos || "nothing"}, expected ${MIN_EXPECTED}`);
  }
  if (sdk !== sdkInstalled) {
    fail(`bundle reports sdk ${sdk || "nothing"}, expected the installed SDK ${sdkInstalled}`);
  }

  // The control that makes the two assertions above mean something. Without the
  // linker flags SwiftPM sets sdk equal to the deployment target, so sdk and
  // minos coming back the same is exactly the failure this gate exists to catch,
  // and it would otherwise satisfy a naive "sdk is set" check.
  if (minos && sdk && minos === sdk) {
    fail(
      `control failed: sdk and minos are both ${sdk}, which is what an unstamped ` +
        "SwiftPM build looks like; the -platform_version flags did not take"
    );
  }

  // The installed copy is what actually draws on screen. A stale install is not
  // a build failure, so this reports rather than fails.
  const installed = "/Applications/Imperator DefaultBrowser.app/Contents/MacOS/DefaultBrowser";
  if (existsSync(installed)) {
    const live = buildVersion(installed);
    if (live.sdk !== sdk) {
      console.log(`note: /Applications copy reports sdk ${live.sdk}; run make install to refresh it`);
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

const { minos, sdk } = buildVersion(bundleBinary);
console.log(`bundle stamps minos ${minos} with sdk ${sdk}, so it runs on ${minos} and draws ${sdk} controls`);
console.log("SDK_STAMP_OK");
