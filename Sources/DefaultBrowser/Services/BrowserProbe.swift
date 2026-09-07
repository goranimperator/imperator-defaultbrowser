import AppKit

/// Headless output for `--list-browsers`, used by the verification scripts in tools/.
/// One tab-separated record per browser; the default is marked with a leading `*`.
enum BrowserProbe {
    /// Headless switch for `--set-default <bundle id>`. Prints the outcome and the
    /// resulting default so a verification script can assert on it.
    static func setDefault(bundleID: String) -> Int32 {
        guard let browser = orderedBrowsers()
            .first(where: { $0.bundleID.lowercased() == bundleID.lowercased() }) else {
            print("no installed browser with bundle id \(bundleID)")
            return 1
        }

        var status: Int32 = 1
        var finished = false
        BrowserService.makeDefault(browser) { error in
            if let error = error as NSError? {
                print("failed: domain=\(error.domain) code=\(error.code) \(error.localizedDescription)")
            } else {
                print("set: \(browser.name)")
                status = 0
            }
            finished = true
        }

        // The result is delivered on the main queue, so the run loop has to keep
        // turning; blocking on a semaphore here would deadlock.
        let deadline = Date().addingTimeInterval(30)
        while !finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !finished { print("timed out waiting for LaunchServices") }
        guard status == 0 else { return status }

        // LaunchServices needs a few seconds to rewrite its handler tables, so poll
        // until the new default shows up rather than reporting a stale read.
        let confirmDeadline = Date().addingTimeInterval(15)
        while Date() < confirmDeadline {
            if BrowserService.currentDefaultBundleID()?.lowercased() == browser.bundleID.lowercased() {
                print("default now: \(browser.bundleID)")
                return 0
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
        }

        print("default still: \(BrowserService.currentDefaultBundleID() ?? "nil")")
        return 1
    }

    static func printRawHandlers() {
        for path in BrowserService.rawHTTPSHandlerPaths() {
            print(path)
        }
    }

    /// Discovery plus the user's saved order, so this prints exactly what the
    /// popover lists.
    static func orderedBrowsers() -> [Browser] {
        BrowserOrderStore.apply(BrowserOrderStore.load(), to: BrowserService.installedBrowsers())
    }

    static func printBrowsers() {
        let currentDefault = BrowserService.currentDefaultBundleID()
        for browser in orderedBrowsers() {
            let marker = browser.bundleID == currentDefault ? "*" : "-"
            print("\(marker)\t\(browser.bundleID)\t\(browser.name)\t\(browser.url.path)")
        }
    }
}
