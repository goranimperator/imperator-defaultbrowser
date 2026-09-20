#!/usr/bin/env node
// Checks the brand book rules that can be read straight out of the source.
// Section numbers refer to imperator-apps-brandbook/BRANDBOOK.md.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const sourceDir = path.join(repoRoot, "Sources", "DefaultBrowser");
const plist = path.join(repoRoot, "Resources", "Info.plist");

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) return swiftFiles(full);
    return full.endsWith(".swift") ? [full] : [];
  });
}

const files = swiftFiles(sourceDir);
const sources = new Map(files.map((file) => [path.relative(repoRoot, file), readFileSync(file, "utf8")]));
const allSource = [...sources.values()].join("\n");

function plistValue(key) {
  return execFileSync("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, plist], {
    encoding: "utf8",
  }).trim();
}

const failures = [];

function require(condition, message) {
  if (!condition) failures.push(message);
}

// §14.2 method 3: no bare accent colour anywhere. Comments are stripped first so
// documenting the rule does not trip it.
function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
}

export function findBareAccentColor(text) {
  return /\baccentColor\b/.test(stripComments(text));
}

for (const [file, text] of sources) {
  if (findBareAccentColor(text)) {
    failures.push(`§14.2 bare accentColor in ${file}`);
  }
}

// Control for that negative assertion: the same check has to fire on a known bad line.
if (!findBareAccentColor(".tint(.accentColor)")) {
  failures.push("control failed: the accentColor check does not fire on a bare accentColor use");
}
if (findBareAccentColor("// never use Color.accentColor\n.tint(AppColors.brand)")) {
  failures.push("control failed: the accentColor check fires on a comment");
}

// §14.1 forced dark mode and §14.2 method 2 accent override, both at launch.
const mainSwift = sources.get("Sources/DefaultBrowser/main.swift") ?? "";
require(
  mainSwift.includes("NSAppearance(named: .darkAqua)"),
  "§14.1 main.swift does not force dark appearance"
);
require(
  mainSwift.includes('UserDefaults.standard.set(0, forKey: "AppleAccentColor")'),
  "§14.2 main.swift does not override the system accent colour"
);

// §2.6 the brand colour is defined once, as the brand book's hex.
const colors = sources.get("Sources/DefaultBrowser/AppColors.swift") ?? "";
require(
  colors.includes("0xa0/255.0") && colors.includes("0x18/255.0"),
  "§2.6 AppColors.brand is not #A01818"
);

// §5.1 panel width, §6.1 surface and dismissal.
require(allSource.includes(".frame(width: 340)"), "§5.1 menu bar panel is not 340pt wide");
require(
  allSource.includes("Color.black.opacity(0.15)"),
  "§6.1 menu bar panel background is not black at 15%"
);

// §6.1 used to be satisfied by NSPopover's own .transient behaviour. The panel
// is drawn by the app now, so the same three promises are checked against
// MenuBarPanel: it is the system popover material, it dismisses on a click
// outside, and it closes on Escape.
const menuBarPanel = sources.get("Sources/DefaultBrowser/MenuBarPanel.swift") ?? "";
require(menuBarPanel !== "", "§6.1 MenuBarPanel.swift is missing");
require(
  menuBarPanel.includes("container.material = .popover"),
  "§6.1 the panel surface is not the system popover material"
);
require(
  menuBarPanel.includes("addGlobalMonitorForEvents"),
  "§6.1 the panel has no click-outside dismissal"
);
require(
  menuBarPanel.includes("event.keyCode == 53"),
  "§6.1 the panel does not close on Escape"
);

// The corner is the whole reason the panel exists. The number is measured, and
// MenuBarPanel.swift carries the measurement; this only catches it being
// changed by hand without one.
require(
  /static let cornerRadius: CGFloat = 18\.25\b/.test(menuBarPanel),
  "§13 MenuBarPanel.cornerRadius is not the measured 18.25"
);

// Nothing may go back to NSPopover: it draws 26.25pt from an sdk 27.0 binary
// and 9.5pt from an sdk 14.0 one, and exposes no radius to set.
require(
  !/\bNSPopover\b/.test(stripComments(allSource)),
  "§6.1 an NSPopover is back; the menu bar panel has to stay app-drawn"
);

// Control for that negative assertion: it has to fire on the thing it forbids,
// and not on the comments in MenuBarPanel.swift that explain why it is gone.
if (!/\bNSPopover\b/.test(stripComments("let popover = NSPopover()"))) {
  failures.push("control failed: the NSPopover check does not fire on a real use");
}
if (/\bNSPopover\b/.test(stripComments("// NSPopover draws its own frame and gives no way to set the radius"))) {
  failures.push("control failed: the NSPopover check fires on a comment");
}

// §8.1 status bar item.
require(
  allSource.includes("NSStatusItem.squareLength"),
  "§8.1 status item does not use squareLength"
);
require(allSource.includes("image.isTemplate = true"), "§8.1 status bar icon is not a template image");

// §9.1 header is the app name with no trailing controls, §9.2 footer order.
const popover = sources.get("Sources/DefaultBrowser/Views/PopoverContentView.swift") ?? "";
require(
  popover.includes('Text("Imperator DefaultBrowser")') && popover.includes(".font(.headline)"),
  "§9.1 popover header does not show the app name as .headline"
);
require(
  popover.indexOf("LaunchAtLoginToggle()") < popover.indexOf('Text("Quit")'),
  "§9.2 footer does not put Open at Login left of the actions"
);
require(
  popover.includes(".padding(.horizontal, 16)") && popover.includes(".padding(.vertical, 12)"),
  "§4.1 header padding is not H:16 V:12"
);
require(popover.includes(".padding(.vertical, 10)"), "§4.1 footer padding is not V:10");

// §7.5 rows, §13 corner radius.
const row = sources.get("Sources/DefaultBrowser/Views/BrowserRow.swift") ?? "";
require(row.includes("cornerRadius: 6"), "§13 browser rows do not use a 6pt corner radius");
require(row.includes("AppColors.brand"), "§7.5 the active row is not marked in brand red");

// §7.2 toggle spec.
require(
  allSource.includes(".toggleStyle(.switch)") &&
    allSource.includes(".scaleEffect(0.55)") &&
    allSource.includes(".tint(AppColors.brand)"),
  "§7.2 Open at Login toggle does not follow the switch spec"
);

// §7.2 on macOS 27: the switch measures 54x24pt, so scaleEffect(0.55) gives
// 29.7x13.2. A hard frame around it only adds invisible padding while reading
// as a size guarantee it does not provide.
const components = sources.get("Sources/DefaultBrowser/Views/Components.swift") ?? "";
require(
  !/Toggle\([\s\S]{0,400}?\.frame\(width:/.test(stripComments(components)),
  "§7.2 the Open at Login toggle still carries a fixed frame"
);

// Control for that negative assertion: it has to fire on the shape it forbids.
if (!/Toggle\([\s\S]{0,400}?\.frame\(width:/.test('Toggle("", isOn: $x)\n.toggleStyle(.switch)\n.frame(width: 36, height: 20)')) {
  failures.push("control failed: the toggle-frame check does not fire on a framed toggle");
}

// §10 About panel.
const about = sources.get("Sources/DefaultBrowser/Views/AboutPanel.swift") ?? "";
require(
  about.includes("width: 300, height: 260"),
  "§10.2 About panel is not 300x260pt"
);
require(
  about.includes("Calendar.current.component(.year, from: Date())"),
  "§10.4 About panel hardcodes the copyright end year"
);

// §15 identity, §17.2 app type.
require(plistValue("CFBundleName") === "Imperator DefaultBrowser", "§15.2 CFBundleName is wrong");
require(
  plistValue("CFBundleDisplayName") === "Imperator DefaultBrowser",
  "§15.2 CFBundleDisplayName is wrong"
);
require(
  plistValue("CFBundleIdentifier") === "com.goranimperator.ImperatorDefaultBrowser",
  "§15.3 bundle identifier does not follow com.goranimperator.Imperator[AppName]"
);
require(plistValue("LSUIElement") === "true", "§17.2 LSUIElement is not true");
require(plistValue("LSMinimumSystemVersion") === "14.0", "§17.2 minimum system version is not 14.0");
require(
  plistValue("NSHumanReadableCopyright").includes("Goran Imperator"),
  "§10.4 NSHumanReadableCopyright is missing"
);
require(
  allSource.includes('ProcessInfo.processInfo.setValue("Imperator DefaultBrowser", forKey: "processName")'),
  "§15.2 process name is not set"
);

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`checked ${sources.size} Swift files and Info.plist against the brand book`);
console.log("BRAND_OK");
