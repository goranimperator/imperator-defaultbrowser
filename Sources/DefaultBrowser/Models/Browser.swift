import AppKit

/// One installed browser that can be made the system default handler for http and https.
struct Browser: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }

    /// Brand book §22.2: Safari and other Cryptex-hosted system apps are symlinks on
    /// macOS 15+. Reading the icon from the unresolved path returns an alias-badged
    /// image, so resolve first.
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
    }
}
