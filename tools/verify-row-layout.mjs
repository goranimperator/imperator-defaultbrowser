#!/usr/bin/env node
// The popover row's switch sits on the row's trailing padding.
//
// This is the defect that prompted the gate. `scaleEffect` scales what a control
// draws and leaves its layout box alone, so the row switch kept a box much wider
// than its drawing and was centred in it. The switch came out 15.45pt from the
// row's edge where the padding is 8, and it read as floating short of the edge
// in every row of the popover.
//
// Nothing in the source said 15.45. The number only exists in the rendered view
// tree, which is why this gate runs the real view through NSHostingView
// (`--measure-row`) and asserts on the geometry rather than on source text.
// `verify-brand.mjs` pins the shape that produces it; this pins the result.

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");

// The BUNDLED binary, not .build/release. AppKit draws the generation of a
// control named by the sdk field in LC_BUILD_VERSION, and SwiftPM stamps that
// with the deployment target, so a plain `swift build` binary draws macOS 14
// controls. The switch is 42x25 there and 54x24 in the shipped build, and
// measuring the wrong one once produced a confident wrong answer that moved the
// switch 3.3pt in the opposite direction.
const binary = path.join(
  repoRoot,
  "build",
  "Imperator DefaultBrowser.app",
  "Contents",
  "MacOS",
  "DefaultBrowser"
);

if (!existsSync(binary)) {
  console.error("FAIL the bundled binary is missing -- run make build");
  process.exit(1);
}

// Refuse to report on an unstamped binary at all. Without this the gate would
// quietly measure macOS 14 controls and pass or fail on the wrong geometry.
let stamp;
try {
  stamp = execFileSync("vtool", ["-show-build-version", binary], { encoding: "utf8" });
} catch (error) {
  console.error(`FAIL could not read LC_BUILD_VERSION: ${error.message}`);
  process.exit(1);
}
const minos = stamp.match(/minos\s+([\d.]+)/)?.[1];
const sdk = stamp.match(/sdk\s+([\d.]+)/)?.[1];
if (!minos || !sdk) {
  console.error("FAIL the bundled binary has no LC_BUILD_VERSION to read");
  process.exit(1);
}
if (sdk === minos) {
  console.error(
    `FAIL the bundled binary is stamped sdk ${sdk} against minos ${minos}, so AppKit will draw ` +
      "macOS 14 era controls and any geometry measured here is not what ships. Build with make build."
  );
  process.exit(1);
}

/// The row's own horizontal padding, from BrowserRow. The switch's trailing edge
/// should land on it.
const ROW_PADDING = 8;
/// Half a point. At 2x that is under one device pixel, which is the most the
/// scaled control can be out by once its frame matches its drawing.
const TOLERANCE = 0.5;

const failures = [];

let output;
try {
  output = execFileSync(binary, ["--measure-row"], { encoding: "utf8" });
} catch (error) {
  console.error(`FAIL --measure-row did not run: ${error.message}`);
  process.exit(1);
}

if (!output.includes("MEASURE_ROW_OK")) {
  console.error("FAIL --measure-row did not complete");
  console.error(output);
  process.exit(1);
}

function number(label) {
  const match = output.match(new RegExp(`${label}:\\s*(-?[\\d.]+)`));
  return match ? Number(match[1]) : NaN;
}

const trailingGap = number("trailing gap");
const switchFrame = output.match(/switch frame: x=([\d.]+) y=([\d.]+) w=([\d.]+) h=([\d.]+)/);

if (!switchFrame) {
  console.error("FAIL could not read the switch frame from --measure-row");
  console.error(output);
  process.exit(1);
}

const drawnWidth = Number(switchFrame[3]);
const drawnHeight = Number(switchFrame[4]);

// The assertion this gate exists for.
if (!(Math.abs(trailingGap - ROW_PADDING) <= TOLERANCE)) {
  failures.push(
    `the row switch sits ${trailingGap}pt from the row's trailing edge, not the ${ROW_PADDING}pt padding ` +
      `(tolerance ${TOLERANCE}pt). A scaled control whose frame is not cut to its drawn size does exactly this.`
  );
}

// The switch is actually drawn, not collapsed to nothing by an over-tight frame.
// Without this, a frame of zero would satisfy the gap check above.
if (!(drawnWidth > 15 && drawnHeight > 8)) {
  failures.push(
    `the row switch is drawn ${drawnWidth}x${drawnHeight}pt, which is too small to be the real control: ` +
      "a frame tighter than the drawing would satisfy the trailing-gap check by clipping it away"
  );
}

// It is also not larger than the row can hold.
if (!(drawnHeight < 32)) {
  failures.push(`the row switch is ${drawnHeight}pt tall, taller than the 32pt row`);
}

// Nothing is painted behind a row, default or not. The switch is the only
// marker. Measured rather than grepped: "no .background in the source" and
// "nothing painted behind the row" are different claims, and only the second
// one is what a user sees. Proved to detect a fill: restoring the old
// RoundedRectangle(cornerRadius: 6).fill(AppColors.brand) makes the default
// row report 1.00 here.
for (const [label, pattern] of [
  ["default row", /row fill alpha, default row:\s*(-?[\d.]+)/],
  ["other row", /row fill alpha, other row:\s*(-?[\d.]+)/],
]) {
  const match = output.match(pattern);
  if (!match) {
    failures.push(`could not read the ${label} fill alpha from --measure-row`);
    continue;
  }
  const alpha = Number(match[1]);
  if (alpha < 0) {
    failures.push(`the ${label} fill alpha could not be sampled (${alpha})`);
  } else if (alpha !== 0) {
    failures.push(
      `the ${label} is painted with a fill (alpha ${alpha}). Rows carry no background: ` +
        "the switch is what marks the default browser."
    );
  }
}

// Control for the tolerance: the value this gate was written against must fail
// it, or the check would pass on the defect it exists to catch.
if (Math.abs(15.45 - ROW_PADDING) <= TOLERANCE) {
  failures.push(
    "control failed: the trailing-gap check accepts 15.45pt, the unframed measurement this gate was written against"
  );
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(
  `row switch drawn ${drawnWidth}x${drawnHeight}pt, trailing gap ${trailingGap}pt against ` +
    `${ROW_PADDING}pt of row padding, no fill behind either row, measured on the sdk ${sdk} bundle`
);
console.log("ROW_LAYOUT_OK");
