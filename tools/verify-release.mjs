#!/usr/bin/env node
// Exercises the packaging half of `make release` without touching git or the
// remote: builds the zip through `make dist`, unpacks it somewhere else, and
// checks that what comes out is a version-stamped bundle whose signature still
// verifies and whose binary runs.
//
// `make release` adds the commit, tag, push and `gh release create` on top of
// this. Those four steps cannot be gated at all: a check that pushed a tag would
// be a release, not a test of one, so packaging is the whole verifiable surface.

import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const APP = "Imperator DefaultBrowser";

// A version that no real release will ever carry, so a stale zip left in dist/
// cannot be mistaken for the one this run produced.
const VERSION = "0.0.0-verify";
const zip = path.join(repoRoot, "dist", `Imperator-DefaultBrowser-${VERSION}.zip`);

const failures = [];
const work = mkdtempSync(path.join(tmpdir(), "imperator-release-check-"));

function run(command, args, options = {}) {
  return execFileSync(command, args, { cwd: repoRoot, encoding: "utf8", ...options });
}

function plistValue(plist, key) {
  return run("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, plist]).trim();
}

try {
  rmSync(zip, { force: true });
  run("make", ["dist", `VERSION=${VERSION}`], { stdio: "pipe" });

  if (!existsSync(zip)) {
    failures.push(`make dist did not produce ${path.relative(repoRoot, zip)}`);
  } else {
    run("/usr/bin/ditto", ["-x", "-k", zip, work], { stdio: "pipe" });

    const unpacked = path.join(work, `${APP}.app`);
    if (!existsSync(unpacked)) {
      failures.push("the zip does not unpack to a single .app at the top level");
    } else {
      const plist = path.join(unpacked, "Contents", "Info.plist");

      const shortVersion = plistValue(plist, "CFBundleShortVersionString");
      if (shortVersion !== VERSION) {
        failures.push(`the packaged bundle reports version ${shortVersion}, expected ${VERSION}`);
      }

      // CFBundleVersion has to be the commit count, never a hand-typed number.
      const expectedBuild = run("git", ["rev-list", "--count", "HEAD"]).trim();
      const build = plistValue(plist, "CFBundleVersion");
      if (build !== expectedBuild) {
        failures.push(`the packaged bundle reports build ${build}, expected ${expectedBuild}`);
      }

      // Editing Info.plist breaks the signature, so the recipe re-signs. If it
      // ever stops doing that, this is what catches it.
      try {
        run("/usr/bin/codesign", ["--verify", "--strict", unpacked], { stdio: "pipe" });
      } catch (error) {
        failures.push(`the packaged bundle fails codesign --verify --strict: ${error.message}`);
      }

      // Control for the version assertion: the source Info.plist must still hold
      // its own version, proving `make dist` stamped the bundle and not the tree.
      const sourceVersion = plistValue(path.join(repoRoot, "Resources", "Info.plist"), "CFBundleShortVersionString");
      if (sourceVersion === VERSION) {
        failures.push("control failed: make dist stamped the source Info.plist instead of the built bundle");
      }

      const binary = path.join(unpacked, "Contents", "MacOS", "DefaultBrowser");
      if (!existsSync(binary)) {
        failures.push("the packaged bundle has no executable at Contents/MacOS/DefaultBrowser");
      } else {
        // The unpacked binary has to actually run. --self-test reads nothing and
        // changes nothing, so it is the safe way to prove that.
        try {
          const output = run(binary, ["--self-test"], { cwd: work, stdio: "pipe" });
          if (!output.includes("SELFTEST_OK")) {
            failures.push(`the packaged binary did not pass its self-test: ${output.trim()}`);
          }
        } catch (error) {
          failures.push(`the packaged binary failed to run: ${error.message}`);
        }
      }

      if (!existsSync(path.join(unpacked, "Contents", "Resources", "AppIcon.icns"))) {
        failures.push("the packaged bundle is missing Contents/Resources/AppIcon.icns");
      }
    }
  }
} catch (error) {
  failures.push(`packaging failed: ${error.message}`);
} finally {
  rmSync(work, { recursive: true, force: true });
  rmSync(zip, { force: true });
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(
  `make dist produced a signed ${VERSION} bundle that unpacks, verifies and runs; source Info.plist untouched`
);
console.log("RELEASE_OK");
