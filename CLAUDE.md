# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
node /Users/goran/.claude/skills/unlazy/scripts/gate-check.mjs GATES.md
```

`GATES.md` holds the acceptance gates with their evidence. Eleven are runnable (`tools/verify-*.mjs`
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

- **SPM** (Package.swift): Swift 5.9 tools, macOS 14+
- **LSUIElement**: menu bar only, no dock icon
- **MVVM**: `BrowserStore` (ObservableObject) → views
- **Persistence**: `~/Library/Application Support/ImperatorDefaultBrowser/order.json` (browser order only)

### Key patterns

- `NSStatusItem` + `NSPopover` (from imperator-menu-bar-folders and imperator-airdrop)
- Status bar glyph and popover header glyph are the Lucide `globe-check` SVG rendered through
  `SVGRenderer` to an `NSImage` with `isTemplate = true`, 14pt like Imperator AirDrop
- `SVGRenderer.swift` is a verbatim copy of the one in imperator-menu-bar-folders. Only its
  `.path` case is reached here, but do not strip the unused `circle`, `rect`, `line`, `polyline`
  and `polygon` cases: keeping the file identical is what lets a parser fix move between the apps
  by copying it across
- Popover height is calculated from constants in `PopoverContentView` and pushed into
  `popover.contentSize`, the same way MenuBarFolders sizes its grid popover
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

`AppDelegate` builds one `BrowserStore` → the popover lists `store.browsers` → a row tap calls
`store.makeDefault` → `BrowserService` sets the handler → the store polls until LaunchServices
agrees. Opening the popover always calls `store.refresh()`, because the default can change from
System Settings or from a browser's own prompt while the app sits idle.

## Structure

```
Sources/DefaultBrowser/
  main.swift              # Bootstrap (.accessory), forced dark mode + red accent, headless flags
  AppDelegate.swift       # Status item, popover, settings window, app menu
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
- **Popover**: 340pt wide, `.transient`, `.background(Color.black.opacity(0.15))`
- **HoverButton / LaunchAtLoginToggle**: opacity 0.45 to 1.0, `.easeInOut(0.2)`, in `Views/Components.swift`
- **Rows**: 6pt corner radius; the default browser row is filled `AppColors.brand`. Rows have no
  hover state on purpose: a highlight tracking the pointer down a short list reads as a glitch
- **Cryptex symlinks**: `Browser.icon` resolves symlinks before reading the icon, and the setter maps
  the Cryptex path back to `/Applications/Safari.app` (§22)
- **SPM note**: asset catalogs do not compile under SPM, so there is no asset catalog here. The red
  accent comes from the UserDefaults override and the menu bar icon is rendered from SVG data
- **App icon deviation**: §16.2 asks for a dark background with a red accent. The shipped
  `AppIcon.icns` is a black squircle with a violet sigil, supplied as finished artwork rather than
  generated, so it is the one place the family palette is not followed
- **Known deviation**: §9.1 says the popover header carries no icon. This app puts a 14pt glyph
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
