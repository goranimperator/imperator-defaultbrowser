#!/usr/bin/env node
// Brand book §7.18. The Settings browser order reorders with the house
// lift-and-slide gesture, not with a system drag session.
//
// This is a shape check on the source, not a behaviour check: how a reorder
// feels cannot be read off a file. What it can catch is the regression that
// matters, someone reaching for `List` + `.onMove` again because it is three
// lines. That swap is invisible in review and only shows up when you drag a row
// and nothing moves until you let go.

import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");

function read(relative) {
  const file = path.join(repoRoot, relative);
  return existsSync(file) ? readFileSync(file, "utf8") : "";
}

/// Line comments are where the forbidden shapes are named and explained, so a
/// naive `includes` on the source would match the prose that says not to use
/// them. Block comments carry the same risk.
function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
}

const settingsPath = "Sources/DefaultBrowser/Views/SettingsView.swift";
const gripPath = "Sources/DefaultBrowser/Views/DragGrip.swift";
const settings = read(settingsPath);
const settingsCode = stripComments(settings);
const grip = read(gripPath);

const failures = [];

function require(condition, message) {
  if (!condition) failures.push(message);
}

require(settings.length > 0, `${settingsPath} is missing`);
require(grip.length > 0, `${gripPath} is missing`);

// The forbidden shapes. §7.18: reordering inside a window never uses a system
// drag session; onDrag/onDrop/draggable are for moving items between windows.
for (const [shape, label] of [
  [".onMove", "a List .onMove reorder"],
  [".onDrag(", "an onDrag system drag session"],
  [".onDrop(", "an onDrop system drag session"],
  [".draggable(", "a draggable system drag session"],
]) {
  require(
    !settingsCode.includes(shape),
    `§7.18 ${settingsPath} still reorders with ${label}`
  );
}

// The required shapes, in the order a drag goes through them.
const required = [
  ["DragGesture(minimumDistance: 3", "§7.18 rows do not start on a plain 3pt drag"],
  ["coordinateSpace: .named(", "§7.18 the drag is not read in the list's own coordinate space"],
  [".simultaneousGesture(", "§7.18 the drag is not simultaneous, so a click no longer reaches the row"],
  ["Animation.spring(response: 0.32, dampingFraction: 0.8)", "§7.18 the settle spring is not the house value"],
  [".scaleEffect(lifted?.id ==", "§7.18 the lifted row does not scale"],
  ["1.03", "§7.18 the lifted row does not scale to 1.03"],
  [".zIndex(", "§7.18 the lifted row is not raised above its neighbours"],
  ["NSHapticFeedbackManager.defaultPerformer.perform(.levelChange", "§7.18 no haptic on lift"],
  ["NSHapticFeedbackManager.defaultPerformer.perform(.alignment", "§7.18 no haptic on a slot change"],
  ['accessibilityAction(named: "Move Up")', "§7.18 no Move Up accessibility action"],
  ['accessibilityAction(named: "Move Down")', "§7.18 no Move Down accessibility action"],
];
for (const [shape, message] of required) {
  require(settingsCode.includes(shape), message);
}

// The lifted shadow: black 0.45, radius 12, y 6.
require(
  /\.black\.opacity\(lifted\?\.id == \w+\.id \? 0\.45 : 0\)/.test(settingsCode) &&
    /radius: lifted\?\.id == \w+\.id \? 12 : 0/.test(settingsCode) &&
    /y: lifted\?\.id == \w+\.id \? 6 : 0/.test(settingsCode),
  "§7.18 the lifted row's shadow is not black 0.45 / radius 12 / y 6"
);

// One write per drop. The commit happens in drop() and move(), never inside the
// drag handler, so dragging across five slots saves once rather than five times.
const dragBody = settingsCode.slice(
  settingsCode.indexOf("private func drag("),
  settingsCode.indexOf("private func drop(")
);
require(dragBody.length > 0, "§7.18 no drag handler to check for mid-drag writes");
require(
  !dragBody.includes("commitOrder()") && !dragBody.includes("store.reorder("),
  "§7.18 the drag handler writes the order mid-drag instead of once on drop"
);
require(
  settingsCode.includes("guard order != current.startOrder else { return }"),
  "§7.18 a drop that changed nothing still writes"
);

// While a row is lifted, model updates to the order are ignored, or the row
// being carried would be yanked back by a refresh landing mid-drag.
require(
  /guard lifted == nil, ids != order else \{ return \}/.test(settingsCode),
  "§7.18 a model update can reorder the list while a row is lifted"
);

// §7.18's drag grip: the drawn dot grip, not a stock hamburger symbol. A stock
// glyph runs the full width of a column beside the app icon.
require(
  settingsCode.includes("DragGrip()"),
  "§7.18 the row has no DragGrip"
);
// The grip is one weight. §7.18 still documents a .tertiary to Color.gray
// crossfade on row hover; that rule is out of date and the app does not follow
// it, so a hover state creeping back into the grip is a regression here.
require(
  !gripCodeHasHover(),
  "the drag grip has a hover state again: it is one weight, set by the caller"
);
function gripCodeHasHover() {
  const code = stripComments(grip);
  return code.includes("hovered") || code.includes(".onHover");
}
require(
  !settingsCode.includes("line.3.horizontal"),
  "§7.18 the row still uses the line.3.horizontal stock symbol as its grip"
);
const gripCode = stripComments(grip);
require(
  gripCode.includes("let dot: CGFloat = 3.5") &&
    gripCode.includes("let columnGap: CGFloat = 1.5") &&
    gripCode.includes("let rowGap: CGFloat = 2.5"),
  "§7.18 the grip's dots are not the half-point sizes that land on whole pixels at 2x"
);

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(
  "Settings reorders with a positioned-row DragGesture: 3pt start, 1.03 lift, house settle spring, haptics, one write per drop, keyboard actions"
);
console.log("REORDER_OK");
