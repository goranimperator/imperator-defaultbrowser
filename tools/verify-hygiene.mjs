#!/usr/bin/env node
// Repository hygiene: no declaration in the source that nothing uses, no em or
// en dashes in anything shipped, and no reference to a file that is gone.
//
// The dash rule is a house rule, not a brand book rule: em and en dashes read as
// machine-written, so hyphens, colons and parentheses are used instead.

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const sourceDir = path.join(repoRoot, "Sources", "DefaultBrowser");

const failures = [];

function walk(dir, predicate) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(full, predicate);
    return predicate(entry.name) ? [full] : [];
  });
}

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
}

// ---------------------------------------------------------------- dead symbols

const swiftFiles = walk(sourceDir, (name) => name.endsWith(".swift"));
const swiftSources = new Map(
  swiftFiles.map((file) => [path.relative(repoRoot, file), readFileSync(file, "utf8")])
);
const allCode = [...swiftSources.values()].map(stripComments).join("\n");

// Type members declared `static let` on an enum used as a namespace: cheap to
// add, easy to leave behind. Anything not referenced outside its own
// declaration is dead.
const namespaces = ["AppColors", "PopoverContentView", "BrowserRow", "SettingsView"];
for (const [file, text] of swiftSources) {
  const code = stripComments(text);
  for (const match of code.matchAll(/^\s*(?:private\s+)?static\s+let\s+(\w+)\s*[:=]/gm)) {
    const [, name] = match;
    if (/^\s*private/.test(match[0])) continue;

    const qualified = namespaces.some((ns) => allCode.includes(`${ns}.${name}`));
    const selfQualified = new RegExp(`\\bSelf\\.${name}\\b`).test(code);
    // Inside its own type the name needs no qualifier at all, so a bare mention
    // anywhere other than the declaration itself counts as a use.
    const bareUses = [...code.matchAll(new RegExp(`\\b${name}\\b`, "g"))].length;
    if (!qualified && !selfQualified && bareUses < 2) {
      failures.push(`dead declaration: static let ${name} in ${file} is never referenced`);
    }
  }
}

// Control: the same scan has to flag a symbol that really is unused.
{
  const probe = "enum AppColors {\n    static let neverUsedProbe = 1\n}\n";
  const found = [...stripComments(probe).matchAll(/^\s*static\s+let\s+(\w+)\s*[:=]/gm)].map((m) => m[1]);
  if (!found.includes("neverUsedProbe")) {
    failures.push("control failed: the dead-declaration scan does not see a static let");
  }
  if (allCode.includes("AppColors.neverUsedProbe")) {
    failures.push("control failed: the probe symbol leaked into the real source");
  }
}

// --------------------------------------------------------------------- dashes

const textFiles = [
  ...["README.md", "CLAUDE.md", "GATES.md", "LICENSE", "Makefile", "Package.swift", ".gitignore"]
    .map((name) => path.join(repoRoot, name))
    .filter(existsSync),
  ...swiftFiles,
  ...walk(path.join(repoRoot, "tools"), (name) => name.endsWith(".mjs")),
  path.join(repoRoot, "Resources", "Info.plist"),
];

// Written as escapes so this file does not fail its own check.
const EN_DASH = "\u2013";
const EM_DASH = "\u2014";
const DASHES = new RegExp(`[${EN_DASH}${EM_DASH}]`);

for (const file of textFiles) {
  const text = readFileSync(file, "utf8");
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    if (DASHES.test(lines[index])) {
      failures.push(`${path.relative(repoRoot, file)}:${index + 1} contains an em or en dash`);
    }
  }
}

// Control: the dash pattern has to fire on both characters.
if (!DASHES.test(`an ${EM_DASH} em dash`)) failures.push("control failed: em dash not detected");
if (!DASHES.test(`an ${EN_DASH} en dash`)) failures.push("control failed: en dash not detected");
if (DASHES.test("a - plain hyphen")) failures.push("control failed: a hyphen is treated as a dash");

// ----------------------------------------------------------- stale references

// Paths named in the docs and the Makefile have to exist. A removed script that
// is still documented sends whoever follows the README into a dead end.
const referenceSources = ["README.md", "CLAUDE.md", "Makefile"]
  .map((name) => path.join(repoRoot, name))
  .filter(existsSync);

for (const file of referenceSources) {
  const text = readFileSync(file, "utf8");
  const referenced = new Set(
    [...text.matchAll(/\b(?:tools|Sources|Resources)\/[A-Za-z0-9_@.*/-]+/g)]
      .map((match) => match[0].replace(/[.,)`]+$/, ""))
  );

  for (const reference of referenced) {
    const target = path.join(repoRoot, reference);
    if (reference.includes("*")) continue;
    if (!existsSync(target)) {
      failures.push(`${path.relative(repoRoot, file)} references ${reference}, which does not exist`);
    }
  }
}

// Control: a path that is definitely absent has to be caught by that existence
// test, so the loop above is not passing because it never checks anything.
if (existsSync(path.join(repoRoot, "tools/definitely-not-here.mjs"))) {
  failures.push("control failed: the existence check reports a missing file as present");
}

// ------------------------------------------------------------------- verdict

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

const counts = [
  `${swiftFiles.length} Swift files scanned for dead declarations`,
  `${textFiles.length} files scanned for em and en dashes`,
  `${referenceSources.length} files scanned for stale path references`,
];
console.log(counts.join(", "));
console.log("HYGIENE_OK");
