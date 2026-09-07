import Foundation

/// Assertions over the pure logic the app depends on, run by `--self-test`.
///
/// There is no XCTest target here on purpose: the executable would have to be
/// split into a library plus a shim and every type made public to be importable,
/// which is a large change for a handful of pure functions. This runs in-process
/// instead, touches neither LaunchServices nor the status bar, and is wired to a
/// gate through `tools/verify-selftest.mjs`.
enum SelfTest {
    static func run() -> Int32 {
        var failures: [String] = []

        func expect(_ condition: Bool, _ description: String) {
            if !condition { failures.append(description) }
        }

        // MARK: Bundle identifier matching

        let chrome = browser("com.google.Chrome", "Google Chrome", "/Applications/Google Chrome.app")

        expect(chrome.hasBundleID("com.google.Chrome"), "exact bundle id should match")
        expect(chrome.hasBundleID("com.google.chrome"), "lowercased bundle id should match")
        expect(chrome.hasBundleID("COM.GOOGLE.CHROME"), "uppercased bundle id should match")
        expect(!chrome.hasBundleID("org.mozilla.firefox"), "a different bundle id must not match")
        expect(!chrome.hasBundleID(nil), "a nil default must not match any browser")
        expect(!chrome.hasBundleID(""), "an empty default must not match any browser")
        // Control for the case-insensitive comparison: the naive check this
        // replaced has to disagree, otherwise the test proves nothing.
        expect(
            chrome.bundleID != "com.google.chrome",
            "control failed: the case-insensitive assertions would pass with a plain == comparison"
        )

        // MARK: Saved order

        let safari = browser("com.apple.Safari", "Safari", "/Applications/Safari.app")
        let firefox = browser("org.mozilla.firefox", "Firefox", "/Applications/Firefox.app")
        let discovered = [chrome, firefox, safari]

        let unsorted = BrowserOrderStore.apply([], to: discovered)
        expect(unsorted.map(\.bundleID) == discovered.map(\.bundleID), "an empty order must not reorder anything")

        let saved = BrowserOrderStore.apply(["com.apple.Safari", "com.google.Chrome"], to: discovered)
        expect(
            saved.map(\.bundleID) == ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox"],
            "a saved order must lead and unlisted browsers must follow"
        )

        let opera = browser("com.operasoftware.Opera", "Opera", "/Applications/Opera.app")
        let vivaldi = browser("com.vivaldi.Vivaldi", "Vivaldi", "/Applications/Vivaldi.app")
        let withNewcomers = BrowserOrderStore.apply(
            ["com.apple.Safari"],
            to: [opera, safari, vivaldi]
        )
        expect(
            withNewcomers.map(\.bundleID)
                == ["com.apple.Safari", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"],
            "browsers missing from the saved order must keep their discovery order"
        )

        let stale = BrowserOrderStore.apply(
            ["com.brave.Browser", "org.mozilla.firefox"],
            to: [chrome, firefox]
        )
        expect(
            stale.map(\.bundleID) == ["org.mozilla.firefox", "com.google.Chrome"],
            "an uninstalled browser in the saved order must be ignored, not leave a hole"
        )

        // MARK: Discovery filters

        expect(
            BrowserService.isInApplicationDirectory("/Applications/Firefox.app"),
            "/Applications must be an application directory"
        )
        expect(
            BrowserService.isInApplicationDirectory(
                "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
            ),
            "the Cryptex mount must be an application directory"
        )
        expect(
            BrowserService.isInApplicationDirectory(NSHomeDirectory() + "/Applications/Foo.app"),
            "~/Applications must be an application directory"
        )
        expect(
            !BrowserService.isInApplicationDirectory(
                NSHomeDirectory() + "/Library/Caches/ms-playwright/firefox-1482/Nightly.app"
            ),
            "a Playwright cache must not be an application directory"
        )
        expect(
            !BrowserService.isInApplicationDirectory(NSHomeDirectory() + "/.cache/puppeteer/chrome/Chrome.app"),
            "a Puppeteer cache must not be an application directory"
        )
        // A path that merely starts with the same characters as a root is not
        // inside it, which is what the trailing slash in the check is for.
        expect(
            !BrowserService.isInApplicationDirectory("/ApplicationsEvil/Firefox.app"),
            "a sibling directory with a shared prefix must not count as /Applications"
        )

        expect(
            BrowserService.declaresWebSchemes(urlTypes: [["CFBundleURLSchemes": ["http", "https"]]]),
            "an app declaring http and https is a browser"
        )
        expect(
            BrowserService.declaresWebSchemes(urlTypes: [["CFBundleURLSchemes": ["HTTP", "HTTPS"]]]),
            "scheme declarations are case-insensitive"
        )
        expect(
            BrowserService.declaresWebSchemes(
                urlTypes: [["CFBundleURLSchemes": ["http"]], ["CFBundleURLSchemes": ["https"]]]
            ),
            "the two schemes may be declared in separate URL types"
        )
        expect(
            !BrowserService.declaresWebSchemes(urlTypes: [["CFBundleURLSchemes": ["https"]]]),
            "an https-only handler is a link handler, not a browser"
        )
        expect(
            !BrowserService.declaresWebSchemes(urlTypes: []),
            "an app declaring no URL types is not a browser"
        )
        expect(
            !BrowserService.declaresWebSchemes(urlTypes: [["CFBundleURLName": "Web"]]),
            "a URL type with no schemes is not a browser"
        )

        for failure in failures {
            print("FAIL \(failure)")
        }
        guard failures.isEmpty else { return 1 }

        print("self-test passed")
        print("SELFTEST_OK")
        return 0
    }

    private static func browser(_ bundleID: String, _ name: String, _ path: String) -> Browser {
        Browser(bundleID: bundleID, name: name, url: URL(fileURLWithPath: path))
    }
}
