# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Toolchain and SDK

`make build` passes `-platform_version` to the linker so the binary reports `minos 14.0` with
`sdk 27.0`. AppKit picks which generation of a control to draw from that sdk field, not from the
running macOS, and SwiftPM would otherwise stamp it with the deployment target and draw macOS 14 era
controls forever. `tools/verify-sdk-stamp.mjs` gates both halves, because losing it is a purely
visual regression that would ship unnoticed. Do not raise `platforms:` to fix a control's look: this
is a public repo promising macOS 14.

Full procedure: `~/Code/imperator/imperator-apps-brandbook/MACOS27-APP-UPGRADE.md`.

## Build

```bash
make install
```

Builds release with SPM, bundles as .app, codesigns with the self-signed `Imperator Dev` identity,
installs to /Applications, and launches. `make install` already kills the running instance first.
Other targets: `make run`, `make build`, `make clean`, `make icon`.

`Resources/AppIcon.icns` is the artwork itself and is checked in; nothing generates it. `make icon`
only re-cuts `Resources/AppIcon.png`, the README preview, from the `.icns`. Run it after replacing
the artwork, or `tools/verify-icon.mjs` fails on the drift.

Signing must use a stable identity, not ad-hoc. The login item registration is keyed to the bundle's
designated requirement, and ad-hoc signing mints a new cdhash per build, so every update would look
like a different app and drop the registration. Override only for throwaway builds:
`make build CODESIGN_IDENTITY=-`

## Release

```bash
make dist VERSION=1.0.0
```

Builds a zip in `dist/`. Touches nothing in git or on the remote.

```bash
make release VERSION=1.0.0
```

Bumps `Resources/Info.plist`, commits, tags `v1.0.0`, pushes, and publishes a GitHub release with
the zip attached. `check-release` gates it on `gh` being installed, a clean tree, the branch being
`main`, and neither the tag nor the release existing yet. That pre-flight is not decoration:
`release` commits before it tags, so a late tag collision would strand a `Release vX` commit with
nothing pointing at it. `CFBundleVersion` comes from `git rev-list --count HEAD` and is never
hand-edited. Full checklist: `~/.claude/skills/imperator-release/SKILL.md`.

## Verify

```bash
make verify
```

Runs every runnable gate in order and quits any running instance first, because `verify-launch.mjs`
needs the field clear. Not a dependency of `release`: failing a release because the app happened to
be open would be its own trap.

The same gates with their recorded evidence, through the ledger:

```bash
node ~/.claude/skills/unlazy/scripts/gate-check.mjs GATES.md
```

`GATES.md` holds the acceptance gates with their evidence. Twelve are runnable (`tools/verify-*.mjs`
plus `swift build` and `make build`), two are manual: the live default-browser switch, because it
mutates a real system setting, and the rendered UI. Add a gate rather than a comment when a
behaviour needs protecting.

Pure logic lives behind `--self-test`, asserted in `Services/SelfTest.swift` and gated by
`tools/verify-selftest.mjs`. There is no XCTest target on purpose: making one would mean splitting
the executable into a library plus a shim and exposing every type, which is a large change for a
handful of pure functions. Put a new pure-logic assertion there rather than reaching for a test
target.

`tools/verify-hygiene.mjs` fails the build on a `static let` nothing references, on an em or en dash
anywhere in the repository, and on a documented path that no longer exists.

## Architecture

- **SPM** (Package.swift): tools 6.4, `swiftLanguageMode(.v5)`, macOS 14 minimum
- **LSUIElement**: menu bar only, no dock icon
- **MVVM**: `BrowserStore` (ObservableObject) → views
- **Persistence**: `~/Library/Application Support/ImperatorDefaultBrowser/order.json` (browser order only)

### Key patterns

- `NSStatusItem` + `MenuBarPanel`, an app-drawn `NSPanel`, not an `NSPopover`. `NSPopover` draws
  its own frame, exposes no radius, and neither frame it draws is the one macOS puts in the menu
  bar. Do not go back to it. The measurements are in `MenuBarPanel.swift`; do not restate them from
  memory
- Status bar glyph and popover header glyph are the Lucide `globe-check` SVG rendered through
  `SVGRenderer` to an `NSImage` with `isTemplate = true`, 14pt like Imperator AirDrop
- `SVGRenderer.swift` is a verbatim copy of the one in imperator-menu-bar-folders. Only its
  `.path` case is reached here, but do not strip the unused `circle`, `rect`, `line`, `polyline`
  and `polygon` cases: keeping the file identical is what lets a parser fix move between the apps
  by copying it across
- Popover height is calculated from constants in `PopoverContentView` and pushed into
  `MenuBarPanel.contentHeight`, the same way MenuBarFolders sizes its grid, so the panel never
  opens clipped
- The global mouse-down monitor skips clicks inside the status item's own window; closing there too
  races with the button's toggle and swallows the open
- `BrowserService` filters LaunchServices handlers by application directory, which is what keeps
  Playwright's and Puppeteer's cached browsers out of the list
- Switching goes through `LSSetDefaultHandlerForURLScheme` because
  `NSWorkspace.setDefaultApplication` returns `NSCocoaErrorDomain 256` for the browser role on
  macOS 14+. The deprecation warning is deliberate and documented in `BrowserService`
- LaunchServices propagates a handler change over 2-4 seconds, so the store shows the new default
  immediately and confirms by polling; never assert on a single read after a switch

### Data flow

`AppDelegate` builds one `BrowserStore` → the panel lists `store.browsers` → a row tap calls
`store.makeDefault` → `BrowserService` sets the handler → the store polls until LaunchServices
agrees. Opening the panel always calls `store.refresh()`, because the default can change from
System Settings or from a browser's own prompt while the app sits idle.

## Structure

```
Sources/DefaultBrowser/
  main.swift              # Bootstrap (.accessory), forced dark mode + red accent, headless flags
  AppDelegate.swift       # Status item, panel, settings window, app menu
  MenuBarPanel.swift      # The menu bar panel: surface, corner, placement, dismissal
  AppColors.swift         # Centralized brand color (AppColors.brand)
  ViewExtensions.swift    # .cursor(.pointingHand), .expandTapTarget()
  Models/Browser.swift
  Services/               # BrowserService, BrowserStore, BrowserOrderStore, GlobeIcon, SVGRenderer, BrowserProbe, SelfTest
  Views/                  # PopoverContentView, BrowserRow, SettingsView, AboutPanel, Components
tools/                    # the verify-*.mjs gate oracles
Resources/                # Info.plist, AppIcon.icns (the artwork), AppIcon.png (README preview)
```

## Brand Book

This app follows the Imperator brand book at `~/Code/imperator/imperator-apps-brandbook/BRANDBOOK.md`.
`tools/verify-brand.mjs` enforces the parts that can be read from source; run it after touching any view.

Key rules:
- **Colors**: always `AppColors.brand`, never inline `Color(red: 0xa0/255, ...)` or bare `Color.accentColor`
- **Dark mode**: forced via `NSApp.appearance = NSAppearance(named: .darkAqua)` in main.swift
- **Accent override**: `UserDefaults.standard.set(0, forKey: "AppleAccentColor")` in main.swift
- **Menu bar panel**: 340pt wide, `NSVisualEffectView` with `.popover` material, and the content
  lays `.background(Color.black.opacity(0.15))` over it. Dismissal and Escape are the panel's own,
  not the delegate's: two monitors closing the same panel raced each other on the toggle
- **HoverButton / LaunchAtLoginToggle**: opacity 0.45 to 1.0, `.easeInOut(0.2)`, in `Views/Components.swift`
- **Rows**: 6pt corner radius, 6pt apart; the default browser row is filled `AppColors.brand`.
  Rows that are not the default take a `Color.white.opacity(0.08)` hover fill over
  `.easeInOut(0.15)`. The red row deliberately has none: clicking it does nothing, so lighting it
  up would promise an action it does not perform
- **Row switch**: `BrowserRow.indicator` is the system `Toggle`, identical to the footer's. It is
  `allowsHitTesting(false)`: the row is the control, so the switch never takes a click of its own,
  which also rules out switching the default browser off, something macOS does not allow. An
  indicator carries `.cursor(.arrow)`, so no toggle in the app ever shows the pointing hand. An
  `NSSwitch` already forces an arrow from its own cursor rect, but stating it in the view keeps the
  outcome from depending on a SwiftUI side effect. The pointing hand stays on the rest of the row
- **Cryptex symlinks**: `Browser.icon` resolves symlinks before reading the icon, and the setter maps
  the Cryptex path back to `/Applications/Safari.app` (§22)
- **SPM note**: asset catalogs do not compile under SPM, so there is no asset catalog here. The red
  accent comes from the UserDefaults override and the menu bar icon is rendered from SVG data
- **App icon deviation**: §16.2 asks for a dark background with a red accent. The shipped
  `AppIcon.icns` is a black squircle with a violet sigil, supplied as finished artwork rather than
  generated, so it is the one place the family palette is not followed
- **Known deviation**: §9.1 says the panel header carries no icon. This app puts a 14pt glyph
  before the name because Imperator AirDrop, EQ, FreeGames and MenuBarFolders all do, and matching
  the family was the explicit requirement

## Conventions

- `@MainActor` on store and delegate classes
- Bundle identifiers are never compared with `==`. Use `Browser.hasBundleID(_:)` or
  `BrowserStore.isDefault(_:)`, because LaunchServices does not always echo an identifier back in
  the case the app's Info.plist spells it
- No em dashes or en dashes anywhere. `tools/verify-hygiene.mjs` fails the build on one
- English only in filenames, comments, UI strings, and file content
- Commit messages in English
- No new libraries or patterns without checking the existing codebase first
- Icon path data derives from Lucide (ISC): keep the attribution header in `GlobeIcon.swift` and the
  Third-party section in README.md
