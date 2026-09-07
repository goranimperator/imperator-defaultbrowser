import SwiftUI

/// Settings window content: the browser order and a rescan button.
struct SettingsView: View {
    @EnvironmentObject private var store: BrowserStore

    static let windowSize = NSSize(width: 400, height: 480)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browser Order")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Drag to set the order the menu bar list uses.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            browserList

            HStack(spacing: 8) {
                Button("Scan for Browsers") { store.refresh() }
                    .buttonStyle(.bordered)
                    .help("Ask macOS again which browsers are installed")

                Button("Reset Order") { store.resetOrder() }
                    .buttonStyle(.borderless)
                    .disabled(!store.hasCustomOrder)
                    .help("Back to alphabetical order")

                Spacer()

                Text(store.browsers.count == 1 ? "1 browser" : "\(store.browsers.count) browsers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(minWidth: Self.windowSize.width, minHeight: Self.windowSize.height)
    }

    @ViewBuilder
    private var browserList: some View {
        if store.browsers.isEmpty {
            // Brand book §7.11.
            VStack(spacing: 8) {
                Image(nsImage: GlobeIcon.statusBarImage(size: 36))
                    .renderingMode(.template)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.tertiary)
                Text("No browsers found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Scan for Browsers") { store.refresh() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Brand book §7.14: .inset for content lists, .onMove for reordering.
            List {
                ForEach(store.browsers) { browser in
                    settingsRow(browser)
                }
                .onMove { source, destination in
                    store.move(from: source, to: destination)
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: .infinity)
        }
    }

    private func settingsRow(_ browser: Browser) -> some View {
        let isDefault = browser.bundleID == store.defaultBundleID
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Image(nsImage: browser.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)

            Text(browser.name)
                .font(.system(size: 13, weight: isDefault ? .medium : .regular))
                .lineLimit(1)

            Spacer(minLength: 8)

            if isDefault {
                Text("DEFAULT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.brand)
                    .clipShape(Capsule())
            } else {
                Button {
                    store.makeDefault(browser) {}
                } label: {
                    Text("Set as default")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(store.isSwitching)
                .cursor(.pointingHand)
                .help("Make \(browser.name) the default browser")
            }
        }
        .padding(.vertical, 2)
    }
}
