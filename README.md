<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Imperator DefaultBrowser app icon">
</p>

<h1 align="center">Imperator DefaultBrowser</h1>

<p align="center">
  Switch the default web browser from the menu bar. Every installed browser gets its
  own row; click one and it takes over http and https.
</p>

## Requirements

Requires macOS 14 or later, Apple silicon. Built and tested on macOS 26 only; older versions are
expected to work but have not been verified.

Install at your own risk. The app is not notarized and carries no Apple Developer signature, so
macOS cannot vouch for it. It is provided as is, with no warranty, under the
[MIT license](LICENSE).

## Install

Download the latest zip from
[Releases](https://github.com/goranimperator/imperator-defaultbrowser/releases), unzip, and move
`Imperator DefaultBrowser.app` to `/Applications`.

The app is signed with a self-signed certificate and is not notarized, so Gatekeeper blocks the
first launch. Right-click the app and choose **Open**, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Imperator DefaultBrowser.app"
```

There is no Dock icon. The app lives in the menu bar behind a globe glyph.

## Use

Click the globe in the menu bar. The popover lists every installed browser, one per row, with the
current default filled in brand red and marked with a checkmark. Click any other row and it becomes
the default browser for http and https. LaunchServices needs a couple of seconds to propagate the
change; the row updates straight away and the app verifies in the background.

**Settings** in the footer opens a window with two controls:

- **Scan for Browsers**: ask macOS again which browsers are installed, after installing or
  removing one.
- **Browser Order**: drag the rows into the order you want the menu bar list to use. **Reset
  Order** goes back to alphabetical. The order is saved to
  `~/Library/Application Support/ImperatorDefaultBrowser/order.json`.

Every row in that window except the current default carries a **Set as default** action, so the
switch can be made from there too.

## Permissions

None. The app requests no Accessibility, Input Monitoring, or Automation grants, and declares no
`NSUsage` keys. It asks LaunchServices which apps handle http and https, reads their bundles for
names and icons, and asks LaunchServices to change the handler.

The one system integration is **Open at Login** in the popover footer. It calls
`SMAppService.mainApp.register()`, which adds the app to Login Items in System Settings. Turning the
toggle off unregisters it.

## What counts as a browser

An app is listed when it handles **both** `http` and `https`, declares those schemes in its
`CFBundleURLTypes`, and lives in a real application directory: `/Applications`,
`/System/Applications`, `/System/Library/CoreServices`, `~/Applications`, or the Cryptex mount that
holds Safari on macOS 15 and later.

That last rule matters more than it sounds. LaunchServices also registers the throwaway browsers
that Playwright, Puppeteer and Selenium unpack into `~/Library/Caches` and `~/.cache`, and those
would otherwise show up as something to switch to.

## How the switch works

`NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` is tried first, but on macOS 14 and
later it refuses to let one app hand the browser role to another and returns
`NSCocoaErrorDomain 256`, "The file couldn't be opened." So the app falls back to
`LSSetDefaultHandlerForURLScheme`, deprecated since macOS 12 and still the only call that moves the
role. Setting either scheme moves both. Either way the app confirms the result by re-reading the
default rather than trusting the return value, and surfaces an error in the popover if the change
never landed.

Bundle identifiers are compared case-insensitively throughout, because LaunchServices does not
always echo one back in the case the app's own `Info.plist` spells it.

## Build

```bash
make install
```

Builds release with SPM, bundles as `.app`, codesigns with the self-signed `Imperator Dev` identity,
installs to `/Applications`, and launches. Other targets: `make run`, `make build`, `make verify`,
`make clean`.

Signing uses a stable identity rather than ad-hoc on purpose. The login item registration is keyed
to the bundle's designated requirement, and ad-hoc signing mints a new hash on every build, so each
update would look like a different app and drop the registration. Override it for a throwaway
build:

```bash
make build CODESIGN_IDENTITY=-
```

## Verify

```bash
make verify
```

Runs every runnable acceptance gate from [GATES.md](GATES.md): code signature, browser discovery,
default detection, ordering, brand book compliance, launch smoke test, app icon, pure-logic
self-test, repository hygiene and the packaged release. It quits any running instance first,
because the launch smoke test needs the field clear. Two gates are deliberately manual, the live
default-browser switch because it mutates a real system setting, and the rendered UI.

The same gates with their recorded evidence, through the ledger:

```bash
node /Users/goran/.claude/skills/unlazy/scripts/gate-check.mjs GATES.md
```

The binary carries a few headless flags the checks use, and they are handy on their own:

```bash
.build/release/DefaultBrowser --self-test
```

```bash
.build/release/DefaultBrowser --list-browsers
```

```bash
.build/release/DefaultBrowser --list-handlers-raw
```

```bash
"build/Imperator DefaultBrowser.app/Contents/MacOS/DefaultBrowser" --set-default com.apple.Safari
```

```bash
open -n "build/Imperator DefaultBrowser.app" --args --settings
```

`--set-default` has to run from inside the signed bundle so LaunchServices sees a real app identity,
and it changes a real system setting. `--self-test` reads and changes nothing.

## Release

Build a zip without touching git or the remote:

```bash
make dist VERSION=1.0.0
```

The version is stamped into the built bundle rather than into the source, so a test zip reports the
version it would ship as without dirtying the working tree.

Cut a full release. This bumps `Resources/Info.plist`, commits, tags `v1.0.0`, pushes, and publishes
a GitHub release with the zip attached:

```bash
make release VERSION=1.0.0
```

Everything that could go wrong is checked before anything changes: `gh` has to be installed, the
working tree clean, the branch `main`, and neither the tag nor the release may already exist. That
pre-flight matters because `release` commits before it tags, so a tag collision discovered late
would leave a `Release vX` commit with nothing pointing at it.

Tags are plain semver (`v1.0.0`); the release title carries the app name.
`CFBundleShortVersionString` comes from `VERSION`, and `CFBundleVersion` from
`git rev-list --count HEAD`, so neither is ever edited by hand. Editing `Info.plist` invalidates the
signature, so both `dist` and `release` re-sign the bundle afterwards.

Run `make verify` first, and confirm the two manual gates still hold.

## Layout

| Path | Role |
|------|------|
| `Sources/DefaultBrowser/main.swift` | Entry point, `.accessory` activation policy, forced dark mode, headless flags |
| `Sources/DefaultBrowser/AppDelegate.swift` | Status item, popover, settings window, app menu with Cmd+Q |
| `Sources/DefaultBrowser/AppColors.swift` | Brand colour |
| `Sources/DefaultBrowser/Models/Browser.swift` | One installed browser, plus case-insensitive identifier matching |
| `Sources/DefaultBrowser/Services/BrowserService.swift` | LaunchServices discovery, filtering, and the two-path setter |
| `Sources/DefaultBrowser/Services/BrowserStore.swift` | `@MainActor ObservableObject`, optimistic update and confirmation polling |
| `Sources/DefaultBrowser/Services/BrowserOrderStore.swift` | The saved order, as JSON in Application Support |
| `Sources/DefaultBrowser/Services/GlobeIcon.swift` | The menu bar glyph, as Lucide SVG path data |
| `Sources/DefaultBrowser/Services/SVGRenderer.swift` | SVG path data to `NSBezierPath` |
| `Sources/DefaultBrowser/Services/BrowserProbe.swift` | Headless output for the verification flags |
| `Sources/DefaultBrowser/Services/SelfTest.swift` | Assertions over the pure logic, run by `--self-test` |
| `Sources/DefaultBrowser/Views/` | SwiftUI: popover, row, settings window, About panel |
| `Resources/` | `Info.plist`, `AppIcon.icns`, and the `AppIcon.png` this README shows |
| `tools/` | The gate oracles behind `GATES.md` |

A SwiftPM executable with no dependencies. `LSUIElement` is true, so there is no Dock icon; the
status item is the entire interface.

Because SwiftPM does not compile asset catalogs, the menu bar icon cannot ship as an image asset. It
is stored as SVG path data, parsed at runtime, and rendered into a template `NSImage` so macOS tints
it for light and dark menu bars. The same reason is why the red accent comes from a `UserDefaults`
override rather than from an `AccentColor` asset.

`Resources/AppIcon.icns` is the app icon artwork itself and is checked in, so there is nothing that
generates it. `make icon` only re-cuts `Resources/AppIcon.png` from it, which is what keeps this
README's preview in sync after the artwork is replaced.

## Third-party

The menu bar glyph is the `globe-check` icon from [Lucide](https://lucide.dev), used under the ISC
license. Portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT); all other
copyright is held by Lucide Contributors 2022. The attribution header in
[`GlobeIcon.swift`](Sources/DefaultBrowser/Services/GlobeIcon.swift) must stay.

## License

[MIT](LICENSE) &copy; Goran Imperator
