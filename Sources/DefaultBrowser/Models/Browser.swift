import AppKit

/// One installed browser that can be made the system default handler for http and https.
struct Browser: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }

    /// Bundle identifiers are case-insensitive to LaunchServices, and it does not
    /// always echo one back in the case the app's Info.plist spells it. Comparing
    /// with `==` therefore misses a match and makes the app report a switch that
    /// did land as failed, so every comparison goes through here.
    func hasBundleID(_ other: String?) -> Bool {
        guard let other else { return false }
        return bundleID.compare(other, options: .caseInsensitive) == .orderedSame
    }

    /// Brand book §22.2: Safari and other Cryptex-hosted system apps are symlinks on
    /// macOS 15+. Reading the icon from the unresolved path returns an alias-badged
    /// image, so resolve first.
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
    }
}
