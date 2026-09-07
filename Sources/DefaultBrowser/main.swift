import AppKit

// Brand book §14.2 method 2: force the red accent regardless of system settings.
// SPM does not compile asset catalogs, so this override is the only accent source (§21.3).
UserDefaults.standard.set(0, forKey: "AppleAccentColor")

// Headless listing mode used by the verification scripts in tools/. Runs before
// NSApplication starts so it never touches the status bar.
if CommandLine.arguments.contains("--list-browsers") {
    BrowserProbe.printBrowsers()
    exit(0)
}

if CommandLine.arguments.contains("--list-handlers-raw") {
    BrowserProbe.printRawHandlers()
    exit(0)
}

// Assertions over the pure logic. Reads nothing and changes nothing, so this one
// is safe to run from the plain SPM binary.
if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}

// Headless switch, mainly for verification: run the binary inside the signed
// bundle so LaunchServices sees a real app identity.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--set-default") {
    let bundleID = CommandLine.arguments.count > flagIndex + 1 ? CommandLine.arguments[flagIndex + 1] : ""
    // A following flag is a forgotten argument, not a bundle identifier.
    guard !bundleID.isEmpty, !bundleID.hasPrefix("-") else {
        FileHandle.standardError.write(Data("usage: --set-default <bundle id>\n".utf8))
        exit(2)
    }
    exit(BrowserProbe.setDefault(bundleID: bundleID))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Brand book §14.1: dark mode is forced, and no app offers an appearance picker.
app.appearance = NSAppearance(named: .darkAqua)

// Top-level code already runs on the main thread, so the main-actor-isolated
// delegate can be created here directly.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
