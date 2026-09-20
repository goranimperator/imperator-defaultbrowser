import SwiftUI

/// Brand book §18.3, matching the popover layout used by Imperator AirDrop, EQ,
/// FreeGames and MenuBarFolders: 14pt glyph + app name header, divider, content,
/// divider, footer with Open at Login on the left and actions on the right.
struct PopoverContentView: View {
    @EnvironmentObject private var store: BrowserStore

    /// Runs once a switch is accepted so the popover can close itself.
    let onSwitched: () -> Void

    /// Opens the settings window, which owns the rescan button and the browser order.
    let onOpenSettings: () -> Void

    // The popover is sized from these constants rather than from SwiftUI's own
    // measurement, the same way MenuBarFolders sizes its grid popover.
    static let headerHeight: CGFloat = 40
    static let footerHeight: CGFloat = 36
    static let listPadding: CGFloat = 8
    /// Rows carry a hover fill, so they need enough air between them for the
    /// highlight to read as one row rather than bleeding into its neighbour.
    static let rowSpacing: CGFloat = 6
    static let maxListHeight: CGFloat = 380
    /// The empty state draws a 36pt glyph plus one line of text where the list would be.
    static let emptyStateHeight: CGFloat = 110
    /// Two lines of caption text plus padding.
    static let errorBannerHeight: CGFloat = 52

    static func listHeight(browserCount: Int) -> CGFloat {
        guard browserCount > 0 else { return emptyStateHeight }
        let rows = CGFloat(browserCount) * BrowserRow.height
        let gaps = CGFloat(max(browserCount - 1, 0)) * rowSpacing
        return min(rows + gaps + listPadding * 2, maxListHeight)
    }

    static func totalHeight(browserCount: Int, hasError: Bool) -> CGFloat {
        let error = hasError ? errorBannerHeight + 1 : 0
        return headerHeight + 1 + listHeight(browserCount: browserCount) + error + 1 + footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 340)
        .background(Color.black.opacity(0.15))
    }

    private var header: some View {
        HStack {
            Image(nsImage: GlobeIcon.statusBarImage(size: 14))
                .renderingMode(.template)
                .frame(width: 14, height: 14)
            Text("Imperator DefaultBrowser")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.browsers.isEmpty {
            emptyState
        } else {
            browserList
        }

        if let errorMessage = store.errorMessage {
            Divider()
            errorBanner(errorMessage)
        }
    }

    /// Brand book §7.14: popover lists are a ScrollView plus LazyVStack, not a List.
    private var browserList: some View {
        ScrollView {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(store.browsers) { browser in
                    BrowserRow(
                        browser: browser,
                        isDefault: store.isDefault(browser)
                    ) {
                        store.makeDefault(browser, onSuccess: onSwitched)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, Self.listPadding)
        }
        .frame(height: Self.listHeight(browserCount: store.browsers.count))
        .disabled(store.isSwitching)
        .opacity(store.isSwitching ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: store.isSwitching)
    }

    /// Brand book §7.11.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(nsImage: GlobeIcon.statusBarImage(size: 36))
                .renderingMode(.template)
                .frame(width: 36, height: 36)
                .foregroundStyle(.tertiary)
            Text("No browsers found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.emptyStateHeight)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HoverButton(action: { store.errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .help("Dismiss")
        }
        .foregroundStyle(AppColors.error)
        .padding(.horizontal, 16)
        .frame(height: Self.errorBannerHeight)
    }

    private var footer: some View {
        HStack {
            LaunchAtLoginToggle()
            Spacer()
            // Brand book §9.2 settings button.
            HoverButton(action: onOpenSettings) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.caption)
            }
            HoverButton(action: { AboutPanel.show() }) {
                Text("About")
                    .font(.caption)
            }
            .help("About Imperator DefaultBrowser")
            HoverButton(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
