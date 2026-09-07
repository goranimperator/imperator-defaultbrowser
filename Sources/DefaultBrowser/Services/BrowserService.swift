import AppKit
import CoreServices

/// Discovers installed browsers and reads or changes the system default handler.
enum BrowserService {
    /// LaunchServices is queried with URLs rather than bare schemes because
    /// `urlsForApplications(toOpen:)` takes a URL. Only the scheme is read, so the
    /// host is a placeholder and nothing is ever fetched.
    private static let httpsProbe = URL(string: "https://example.com")!
    private static let httpProbe = URL(string: "http://example.com")!

    /// Only apps living in a real application directory qualify. LaunchServices also
    /// registers throwaway browsers that Playwright, Puppeteer and Selenium unpack into
    /// caches, and those must never be offered as something to switch to.
    private static var applicationRoots: [String] {
        [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices",
            // Safari and friends live behind a Cryptex mount on macOS 15+ (§22.1).
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]
    }

    // MARK: - Discovery

    static func installedBrowsers() -> [Browser] {
        let workspace = NSWorkspace.shared
        let httpsHandlers = workspace.urlsForApplications(toOpen: httpsProbe)
        let httpHandlers = Set(
            workspace.urlsForApplications(toOpen: httpProbe).map { $0.standardizedFileURL.path }
        )

        var seenBundleIDs = Set<String>()
        var browsers: [Browser] = []

        for url in httpsHandlers {
            let path = url.standardizedFileURL.path

            // A browser handles both schemes. Something that only claims https is a
            // link handler, not a browser.
            guard httpHandlers.contains(path) else { continue }
            guard isInApplicationDirectory(path) else { continue }
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            guard bundleID != Bundle.main.bundleIdentifier else { continue }
            guard declaresWebSchemes(bundle) else { continue }
            guard seenBundleIDs.insert(bundleID).inserted else { continue }

            browsers.append(
                Browser(bundleID: bundleID, name: displayName(for: url, bundle: bundle), url: url)
            )
        }

        // Alphabetical is the built-in order. Settings can override it per user.
        return browsers.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Every https handler LaunchServices knows about, unfiltered. Only used by
    /// `--list-handlers-raw`, which gives the discovery test a positive control: the
    /// raw list contains the cache-unpacked browsers that `installedBrowsers()` drops.
    static func rawHTTPSHandlerPaths() -> [String] {
        NSWorkspace.shared.urlsForApplications(toOpen: httpsProbe).map { $0.path }
    }

    static func currentDefaultBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: httpsProbe) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    // MARK: - Switching

    /// Hands the http and https roles to the given browser.
    ///
    /// The modern API is tried first so this keeps working if Apple opens it up, but
    /// on macOS 14 and later it refuses to let one app give the browser role to
    /// another and returns NSCocoaErrorDomain 256, "The file couldn't be opened."
    /// The LaunchServices call it replaced is still honoured, so that is the
    /// fallback. Either way the caller confirms the result by re-reading the
    /// default rather than trusting the return value.
    static func makeDefault(_ browser: Browser, completion: @escaping (Error?) -> Void) {
        let workspace = NSWorkspace.shared
        let target = settableURL(for: browser)

        workspace.setDefaultApplication(at: target, toOpenURLsWithScheme: "https") { httpsError in
            guard httpsError == nil else {
                let fallbackError = legacySetHandler(bundleID: browser.bundleID)
                DispatchQueue.main.async { completion(fallbackError) }
                return
            }

            // https moved but http is a separate role. Half a switch is worse than
            // none, so if the second call fails the legacy setter takes over rather
            // than leaving the two schemes pointing at different browsers.
            workspace.setDefaultApplication(at: target, toOpenURLsWithScheme: "http") { httpError in
                let fallbackError = httpError == nil
                    ? nil
                    : legacySetHandler(bundleID: browser.bundleID)
                DispatchQueue.main.async { completion(fallbackError) }
            }
        }
    }

    /// LaunchServices' own setter, deprecated since macOS 12 but still the only call
    /// that actually moves the browser role. Setting either scheme moves both, so a
    /// single success is enough; the schemes are attempted in the order that works.
    ///
    /// The deprecation warning this produces is deliberate and left visible: the day
    /// `NSWorkspace.setDefaultApplication` starts working for the browser role, this
    /// whole fallback can go.
    private static func legacySetHandler(bundleID: String) -> Error? {
        var lastFailure: OSStatus = noErr

        for scheme in ["http", "https"] {
            let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString)
            if status == noErr { return nil }
            lastFailure = status
        }

        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(lastFailure),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "macOS refused the change (OSStatus \(lastFailure)). Set it in System Settings > Desktop & Dock."
            ]
        )
    }

    /// LaunchServices reports Cryptex-hosted system apps at their real mount path
    /// under /System/Volumes/Preboot/Cryptexes, and `setDefaultApplication(at:)`
    /// refuses that path with "The file couldn't be opened." The visible symlink
    /// (/Applications/Safari.app) is accepted, so map back to it before setting.
    private static func settableURL(for browser: Browser) -> URL {
        let cryptexPrefix = "/System/Volumes/Preboot/Cryptexes/App"
        let path = browser.url.standardizedFileURL.path
        guard path.hasPrefix(cryptexPrefix) else { return browser.url }

        let candidates = [
            String(path.dropFirst(cryptexPrefix.count)),
            "/Applications/" + browser.url.lastPathComponent,
        ]

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            // Guard against a same-named app at the canonical path being a different
            // application than the one the row represents.
            guard Bundle(path: candidate)?.bundleIdentifier?.lowercased()
                    == browser.bundleID.lowercased() else { continue }
            return URL(fileURLWithPath: candidate)
        }

        return browser.url
    }

    // MARK: - Filters

    /// Internal rather than private so `--self-test` can exercise it without a
    /// bundle on disk. Same for `declaresWebSchemes(urlTypes:)` below.
    static func isInApplicationDirectory(_ path: String) -> Bool {
        applicationRoots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private static func declaresWebSchemes(_ bundle: Bundle) -> Bool {
        declaresWebSchemes(urlTypes: bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? [])
    }

    static func declaresWebSchemes(urlTypes: [[String: Any]]) -> Bool {
        var schemes = Set<String>()
        for type in urlTypes {
            for scheme in type["CFBundleURLSchemes"] as? [String] ?? [] {
                schemes.insert(scheme.lowercased())
            }
        }
        return schemes.contains("http") && schemes.contains("https")
    }

    private static func displayName(for url: URL, bundle: Bundle) -> String {
        // Finder's display name gives "Google Chrome" where CFBundleName gives "Chrome".
        let fileName = FileManager.default.displayName(atPath: url.path)
        if !fileName.isEmpty, fileName != url.lastPathComponent {
            return fileName
        }
        if let display = bundle.infoDictionary?["CFBundleDisplayName"] as? String { return display }
        if let name = bundle.infoDictionary?["CFBundleName"] as? String { return name }
        return url.deletingPathExtension().lastPathComponent
    }
}
