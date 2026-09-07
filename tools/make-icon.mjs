#!/usr/bin/env node
// Regenerates Resources/AppIcon.icns.
//
// The icon follows the Imperator family look used by the sibling apps: a
// squircle with a vertical gradient and the three-armed Imperator sigil
// centred on it. This app's variant is a near-black squircle with the sigil in
// brand red (#A01818), per brand book §16.
//
// Rasterizing is done by headless Google Chrome, which is already a dependency
// of nothing else here but is guaranteed present on this machine. The generated
// SVG is written next to this script so the shape stays reviewable.

import { mkdtempSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const svgPath = path.join(repoRoot, "tools", "appicon.svg");
const icnsPath = path.join(repoRoot, "Resources", "AppIcon.icns");

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const CANVAS = 1024;
// macOS app icons leave a transparent margin; 832pt of art inside 1024pt matches
// what Imperator AppIcons produces for the other apps in this family.
const ART = 832;
const BRAND = "#a01818";

/** Apple's icon shape is a superellipse, not a plain rounded rectangle. */
function squirclePath(size, exponent = 5, samples = 720) {
  const radius = size / 2;
  const center = CANVAS / 2;
  const points = [];
  for (let i = 0; i < samples; i++) {
    const theta = (i / samples) * 2 * Math.PI;
    const cos = Math.cos(theta);
    const sin = Math.sin(theta);
    const x = Math.sign(cos) * Math.abs(cos) ** (2 / exponent) * radius;
    const y = Math.sign(sin) * Math.abs(sin) ** (2 / exponent) * radius;
    points.push(`${(center + x).toFixed(3)},${(center + y).toFixed(3)}`);
  }
  return `M ${points.join(" L ")} Z`;
}

// One arm of the sigil, in the master sigil coordinate space (viewBox -80..80).
// Same path data as imperator-crt-image/sigil.svg.
const SIGIL_ARM = `
  M 4.5 22.8
  L 4.5 64
  C 4.5 70, 10 69.41, 12 69.41
  A 118.58 118.58 0 0 0 58.51 54.56
  A 80 80 0 0 1 -58.51 54.56
  A 118.58 118.58 0 0 0 -12 69.41
  C -10 69.41, -4.5 69.41, -4.5 64
  L -4.5 22.8
  A 8 8 0 0 0 -8.65 15.79
  L 8.65 15.79
  A 8 8 0 0 0 4.5 22.8
  Z
`.trim();

// The sigil fills 62% of the squircle, which matches the sibling icons.
const sigilScale = (ART * 0.62) / 160;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS}" height="${CANVAS}" viewBox="0 0 ${CANVAS} ${CANVAS}">
  <defs>
    <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#252525"/>
      <stop offset="0.55" stop-color="#101010"/>
      <stop offset="1" stop-color="#050505"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.14"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0.02"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <filter id="plateShadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000000" flood-opacity="0.45"/>
    </filter>
    <g id="sigilArm"><path d="${SIGIL_ARM}"/></g>
  </defs>

  <g filter="url(#plateShadow)">
    <path d="${squirclePath(ART)}" fill="url(#plate)"/>
  </g>
  <path d="${squirclePath(ART)}" fill="url(#sheen)"/>
  <path d="${squirclePath(ART)}" fill="none" stroke="#ffffff" stroke-opacity="0.10" stroke-width="2"/>

  <g transform="translate(${CANVAS / 2} ${CANVAS / 2}) scale(${sigilScale.toFixed(5)})" fill="${BRAND}">
    <use href="#sigilArm"/>
    <use href="#sigilArm" transform="rotate(120)"/>
    <use href="#sigilArm" transform="rotate(240)"/>
    <path fill-rule="evenodd" d="M 18 0 A 18 18 0 1 0 -18 0 A 18 18 0 1 0 18 0 Z M 9 0 A 9 9 0 1 0 -9 0 A 9 9 0 1 0 9 0 Z"/>
  </g>
</svg>
`;

writeFileSync(svgPath, svg);
console.log(`wrote ${path.relative(repoRoot, svgPath)}`);

if (!existsSync(CHROME)) {
  console.error(`Google Chrome not found at ${CHROME}; cannot rasterize.`);
  process.exit(1);
}

const work = mkdtempSync(path.join(tmpdir(), "imperator-icon-"));
try {
  const html = path.join(work, "icon.html");
  writeFileSync(
    html,
    `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:transparent}</style>${svg}`
  );

  execFileSync(
    CHROME,
    [
      "--headless=new",
      "--disable-gpu",
      "--hide-scrollbars",
      "--force-device-scale-factor=1",
      "--default-background-color=00000000",
      `--window-size=${CANVAS},${CANVAS}`,
      `--screenshot=${path.join(work, "icon-1024.png")}`,
      `file://${html}`,
    ],
    { stdio: ["ignore", "ignore", "pipe"] }
  );

  const master = path.join(work, "icon-1024.png");
  const iconset = path.join(work, "AppIcon.iconset");
  mkdirSync(iconset);

  // The sizes iconutil expects for a complete .icns.
  const variants = [
    ["icon_16x16.png", 16],
    ["icon_16x16@2x.png", 32],
    ["icon_32x32.png", 32],
    ["icon_32x32@2x.png", 64],
    ["icon_128x128.png", 128],
    ["icon_128x128@2x.png", 256],
    ["icon_256x256.png", 256],
    ["icon_256x256@2x.png", 512],
    ["icon_512x512.png", 512],
    ["icon_512x512@2x.png", 1024],
  ];

  for (const [name, size] of variants) {
    execFileSync("/usr/bin/sips", ["-z", String(size), String(size), master, "--out", path.join(iconset, name)], {
      stdio: ["ignore", "ignore", "pipe"],
    });
  }

  execFileSync("/usr/bin/iconutil", ["-c", "icns", iconset, "-o", icnsPath], { stdio: "inherit" });
  console.log(`wrote ${path.relative(repoRoot, icnsPath)}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
