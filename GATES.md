# Gates: Imperator DefaultBrowser

OWNS: Package.swift, Makefile, README.md, LICENSE, CLAUDE.md, GATES.md, .gitignore, Resources/**, Sources/**, tools/**

Scope: A brand-book-compliant macOS menu bar app that lists every installed browser one per row in a 340pt popover, switches the system default browser on click, and exposes a settings window for rescanning and reordering.

Environment for every runnable gate: macOS 26.6.2 (25G83), Swift 6.3.3, zsh, working directory = repository root.

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
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=control: dropped 2 cached throwaway browser(s) | DISCOVERY_OK

- [x] G4: The browser reported as default is the one macOS has registered for https
  CHECK: node tools/verify-default-detection.mjs
  EXPECT: DEFAULT_DETECTION_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=app and LaunchServices plist agree: com.google.Chrome | DEFAULT_DETECTION_OK

- [x] G5: Ordering is alphabetical by default and honours a saved custom order
  CHECK: node tools/verify-order.mjs
  EXPECT: ORDER_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=default order alphabetical, saved order honoured, unlisted browsers last | ORDER_OK

- [x] G6: The source and Info.plist satisfy the brand book rules that can be read statically
  CHECK: node tools/verify-brand.mjs
  EXPECT: BRAND_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=checked 17 Swift files and Info.plist against the brand book | BRAND_OK

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

- [x] G10: The popover, the settings window and the app icon render as specified
  EVIDENCE: Screenshots taken from the signed bundle running out of /Applications. Popover: 340pt wide, header is the 14pt Lucide globe-check glyph plus "Imperator DefaultBrowser" in .headline, one row per browser, the default row (Safari) filled #A01818 with a white circle holding a red checkmark, Google Chrome and Firefox carrying plain white circles, no row hover state, footer reads Open at Login / Settings / About / Quit. Settings window: 400x480, "Browser Order" plus the drag hint, drag handles on every row, Safari carrying the brand-red DEFAULT capsule and both other rows a white "Set as default" action, footer "Scan for Browsers" / "Reset Order" / "3 browsers". App icon: NSWorkspace.icon(forFile:) on /Applications/Imperator DefaultBrowser.app renders the delivered artwork at 1024x1024, a black squircle with the violet Imperator sigil, and the .icns inside the installed bundle is byte-identical to Resources/AppIcon.icns (md5 8cbbdebb5f6aab05592f8b90d4602550).

- [x] G11: Default-browser matching is case-insensitive and order application is stable
  CHECK: node tools/verify-selftest.mjs
  EXPECT: SELFTEST_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=self-test passed | SELFTEST_OK

- [x] G12: No dead declarations, no em or en dashes, and no stale references in source or docs
  CHECK: node tools/verify-hygiene.mjs
  EXPECT: HYGIENE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=17 Swift files scanned for dead declarations, 34 files scanned for em and en dashes, 3 files scanned for stale path references | HYGIENE_OK

- [x] G13: The release flow produces a signed, version-stamped zip that unpacks to a launchable bundle
  CHECK: node tools/verify-release.mjs
  EXPECT: RELEASE_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=make dist produced a signed 0.0.0-verify bundle that unpacks, verifies and runs; source Info.plist untouched | RELEASE_OK
