# Gates: Imperator DefaultBrowser

OWNS: Package.swift, Makefile, README.md, LICENSE, CLAUDE.md, GATES.md, .gitignore, Resources/**, Sources/**, tools/**

Scope: A brand-book-compliant macOS menu bar app that lists every installed browser one per row in a 340pt popover, switches the system default browser on click, and exposes a settings window for rescanning and reordering.

Environment for every runnable gate: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4, macOS SDK 27.0, zsh, working directory = repository root.

- [x] G1: The release build compiles
  CHECK: swift build -c release >/dev/null 2>&1 && echo BUILD_OK
  EXPECT: BUILD_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=BUILD_OK

- [x] G2: The app bundle is produced and satisfies its designated requirement
  CHECK: make build >/dev/null 2>&1 && codesign --verify --strict "build/Imperator DefaultBrowser.app" && echo BUNDLE_SIGNED_OK
  EXPECT: BUNDLE_SIGNED_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=BUNDLE_SIGNED_OK

- [x] G3: Discovery lists real installed browsers and drops cache-unpacked ones
  CHECK: node tools/verify-discovery.mjs
  EXPECT: DISCOVERY_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=filtered 5 handlers down to 4 browsers | control: dropped 1 handler(s) outside every application root: /Users/goran/.ScreamingFrogSEOSpider/chrome/147.0.7727.102-sf1/Chromium.app | DISCOVERY_OK. The control is stated against the application roots rather than a list of cache markers, because the roots are what BrowserService filters on and a marker list goes stale: the Playwright cache this gate first caught is gone from the machine, and Screaming Frog's unpacked Chromium took its place under ~/.ScreamingFrogSEOSpider, which no marker matched. Both controls were proved to fire: narrowing ALLOWED_ROOTS so that /Applications counts as outside makes the gate report the three survivors, and widening it to cover ~/.ScreamingFrogSEOSpider makes the gate report that nothing was left to filter.

- [x] G4: The browser reported as default is the one macOS has registered for https
  CHECK: node tools/verify-default-detection.mjs
  EXPECT: DEFAULT_DETECTION_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=app and LaunchServices plist agree: com.apple.Safari | DEFAULT_DETECTION_OK

- [x] G5: Ordering is alphabetical by default and honours a saved custom order
  CHECK: node tools/verify-order.mjs
  EXPECT: ORDER_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=default order alphabetical, saved order honoured, unlisted browsers last | ORDER_OK

- [x] G6: The source and Info.plist satisfy the brand book rules that can be read statically
  CHECK: node tools/verify-brand.mjs
  EXPECT: BRAND_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=checked 18 Swift files and Info.plist against the brand book | BRAND_OK

- [x] G7: The signed bundle launches, stays up, and exits cleanly without stderr noise
  CHECK: node tools/verify-launch.mjs
  EXPECT: LAUNCH_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=app stayed up for 3s and exited on SIGTERM (signal SIGTERM) | LAUNCH_OK

- [x] G8: The shipped app icon is the delivered artwork, complete at every size, and the README preview is cut from it
  CHECK: node tools/verify-icon.mjs
  EXPECT: ICON_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=10 representations at their declared sizes, README preview cut from the same .icns | ICON_OK

- [x] G9: Clicking a row actually moves the system default browser
  EVIDENCE: Verified end to end on macOS 26.6.2 from inside the signed bundle. NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:) returns NSCocoaErrorDomain 256 ("The file couldn't be opened.") for every browser on this OS, so the LSSetDefaultHandlerForURLScheme fallback is what carries the change. Safari to Google Chrome landed but took longer than 15 seconds to show up in urlForApplication(toOpen:); Chrome back to Safari confirmed in 2.2 seconds. That measurement is what raised BrowserStore.confirmationWindow from 9.6 seconds to 60: the old window gave up on a switch that had in fact landed and showed a false failure banner. Safari re-read as the default at 5, 10, 15, 20, 25 and 30 seconds after the last switch, so it holds rather than being reverted. Note for re-verification: this gate mutates a real system setting, so it is deliberately manual rather than wired into the checker.

- [x] G10: The menu bar panel, the settings window and the app icon render as specified
  EVIDENCE: Measured off the signed bundle running out of /Applications on macOS 27.0 (26A428). The menu bar surface is a MenuBarPanel, an app-drawn NSPanel, not an NSPopover: the window measures 340x248pt with no arrow margin, where the popover it replaced measured 366x274. Corner: captured with screencapture -x -o -l, which returns the window alone with its own alpha and no shadow, then a least-squares circle fitted to the bottom-left arc. The panel fits 36.15 device px = 18.08pt at rms 0.19 over 30 arc points. The same fitter on the popover captures from the previous release returns 8.44pt for an sdk 14.0 binary and 18.87pt for an sdk 27.0 one, and the sdk 27.0 figure is an underestimate because that corner is .continuous while this fitter assumes a circle; MenuBarPanel.swift records the author's own measurements of 9.5 and 26.25 for those two. Whichever fitter is used, the panel is neither of the popover shapes, which is the point of the change. MenuBarPanel.cornerRadius stays at the measured 18.25 and verify-brand.mjs fails if it is edited without one. Dismissal, counted on the real window: after opening 1 panel window, after Escape 0, after reopening 1, after a click outside 0. Content: header is the 14pt Lucide globe-check glyph plus "Imperator DefaultBrowser" in .headline, one row per browser, each carrying the system switch, the default row filled #A01818, rows 6pt apart, footer reads Open at Login / Settings / About / Quit. The switch is the real Toggle, the same control the footer uses. Measured earlier from captures: an off row switch bounds 30.0x14.0pt, the footer switch 33.5x15.0pt, a real System Settings switch 36.0x16.0pt, ratios 2.14, 2.23 and 2.25 to 1, equal within the one-pixel error at 2x. Cursor: nothing in the app changes it. The row, the switch and every other hovered element keep the macOS default arrow, and no cursor call is left in Sources. Note for whoever repeats this: Imperator CRT Overlay was running and paints scanlines over the whole screen, so a plain screencapture of the panel looks washed out; the corner figure above comes from the alpha silhouette, which the overlay cannot reach. Settings window: 400x480, "Browser Order" plus the drag hint, drag handles on every row, the default carrying the brand-red DEFAULT capsule and every other row a white "Set as default" action, footer "Scan for Browsers" / "Reset Order" / the browser count. App icon: NSWorkspace.icon(forFile:) on the installed bundle renders the delivered artwork at 1024x1024, a black squircle with the violet Imperator sigil, and the .icns inside it is byte-identical to Resources/AppIcon.icns (md5 12c7b0ba7286cc89a612d78cb903c765, the artwork delivered on 2026-09-25). Resources/AppIcon.png, the README preview, is the 256px slice of that same .icns copied whole rather than downscaled to 128: the README renders it at width 128, which is 256 physical pixels on a Retina display.

- [x] G11: Default-browser matching is case-insensitive and order application is stable
  CHECK: node tools/verify-selftest.mjs
  EXPECT: SELFTEST_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=self-test passed | SELFTEST_OK

- [x] G12: No dead declarations, no em or en dashes, and no stale references in source or docs
  CHECK: node tools/verify-hygiene.mjs
  EXPECT: HYGIENE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=18 Swift files scanned for dead declarations, 36 files scanned for em and en dashes, 3 files scanned for stale path references | HYGIENE_OK

- [x] G13: The release flow produces a signed, version-stamped zip that unpacks to a launchable bundle
  CHECK: node tools/verify-release.mjs
  EXPECT: RELEASE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=make dist produced a signed 0.0.0-verify bundle that unpacks, verifies and runs; source Info.plist untouched | RELEASE_OK

- [x] G14: The shipped binary draws macOS 27 controls while still running on macOS 14
  CHECK: node tools/verify-sdk-stamp.mjs
  EXPECT: SDK_STAMP_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=bundle stamps minos 14.0 with sdk 27.0, so it runs on 14.0 and draws 27.0 controls | SDK_STAMP_OK
