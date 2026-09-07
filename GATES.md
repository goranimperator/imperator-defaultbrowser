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
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=checked 16 Swift files and Info.plist against the brand book | BRAND_OK

- [x] G7: The signed bundle launches, stays up, and exits cleanly without stderr noise
  CHECK: node tools/verify-launch.mjs
  EXPECT: LAUNCH_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=app stayed up for 3s and exited on SIGTERM (signal SIGTERM) | LAUNCH_OK

- [x] G8: The app icon is a complete .icns with a 1024px representation
  CHECK: node tools/verify-icon.mjs
  EXPECT: ICON_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/goran/Code/imperator/imperator-menu-bar-default-browser; path=bdfa726d98c4/47 entries; output=10 representations present, largest is 1024x1024 | ICON_OK

- [x] G9: Clicking a row actually moves the system default browser
  EVIDENCE: Verified end to end on macOS 26.6.2. NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:) returns NSCocoaErrorDomain 256 ("The file couldn't be opened.") for every browser on this OS, including from inside the signed bundle, so the LaunchServices fallback is what carries the change. The default handler moved Google Chrome -> Firefox and back to Google Chrome, each confirmed by re-reading urlForApplication(toOpen:) for both http and https after LaunchServices propagated (2-4s). Note for re-verification: this gate mutates a real system setting, so it is deliberately manual rather than wired into the checker.

- [x] G10: The popover and the settings window render as specified
  EVIDENCE: Screenshots taken from the running signed bundle. Popover: 340pt wide, header is the 14pt Lucide globe-check glyph plus "Imperator DefaultBrowser" in .headline, one row per browser, the default row filled #A01818 with a white circle and a red checkmark, no row hover state, footer reads Open at Login / Settings / About / Quit. Settings window: 400x480, drag-reorderable list with DEFAULT badge, "Scan for Browsers" and "Reset Order" buttons and a browser count. A scripted drag of Safari to the top rewrote order.json to ["com.apple.Safari","org.mozilla.firefox","com.google.Chrome"] and the list redrew in that order.
