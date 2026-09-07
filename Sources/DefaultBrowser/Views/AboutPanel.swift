import SwiftUI
import AppKit

/// Brand book §10.2: NSPanel 300x260pt, transparent title bar, dark background.
@MainActor
enum AboutPanel {
    private static var panel: NSPanel?

    static func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 260)

        let aboutPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        aboutPanel.titlebarAppearsTransparent = true
        aboutPanel.titleVisibility = .hidden
        aboutPanel.isMovableByWindowBackground = true
        aboutPanel.isReleasedWhenClosed = false
        aboutPanel.backgroundColor = AppColors.backgroundNS
        aboutPanel.appearance = NSAppearance(named: .darkAqua)
        aboutPanel.contentView = hostingView
        aboutPanel.center()
        aboutPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = aboutPanel
    }
}

/// Brand book §10.3.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Brand book §10.4: the end year is computed, never hardcoded.
    private var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\u{00A9} 1986-\(year) Goran Imperator"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            Text("Imperator DefaultBrowser")
                .font(.headline)

            Text("Version \(version) (Build \(build))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Link("goranimperator.com", destination: URL(string: "https://www.goranimperator.com")!)
                .font(.caption)
                .foregroundStyle(AppColors.brand)

            Spacer()
        }
        .padding(24)
        .frame(width: 300, height: 260)
    }
}
