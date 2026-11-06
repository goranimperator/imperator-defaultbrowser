import AppKit
import SwiftUI

/// Settings window content: the browser order and a rescan button.
///
/// Nothing here overrides the mouse cursor. The system pointer is what a window
/// is supposed to show.
struct SettingsView: View {
    @Environment(BrowserStore.self) private var store

    static let windowSize = NSSize(width: 400, height: 480)

    /// Display order as bundle identifiers. Follows the store, except while a
    /// row is lifted, when it is the live order the other rows slide into.
    @State private var order: [String] = []
    @State private var lifted: LiftedRow?
    /// Height of one row including its gaps, measured off a rendered row. The
    /// starting value is that measurement on macOS 27, so the first layout is
    /// already right rather than settling a frame later.
    @State private var rowPitch: CGFloat = 36

    private struct LiftedRow {
        let id: String
        /// Pointer position in the list's coordinate space.
        var pointerY: CGFloat
        /// Pointer minus row centre when lifted, so the row stays where it was
        /// grabbed instead of jumping to centre under the pointer.
        let grab: CGFloat
        let startOrder: [String]
    }

    private static let space = "browserOrderList"
    /// Brand book §7.18, the house settle for both rows and grids.
    private static let settle = Animation.spring(response: 0.32, dampingFraction: 0.8)
    /// Vertical whitespace around a row's fill, which is what sets the pitch
    /// between rows.
    private static let gap: CGFloat = 6
    /// How far a row's fill reaches past its content, and brand book §7.5's row
    /// padding. The list bleeds out by exactly this much, so the fill sits
    /// proud of the window margin while the content inside it lands on that
    /// margin, in line with the heading and the buttons above and below.
    private static let fillInset: CGFloat = 8

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
        .onAppear { order = store.browsers.map(\.id) }
        .onChange(of: store.browsers.map(\.id)) { _, ids in
            // A rescan, a reset, or a committed reorder lands here. A lifted row
            // owns the order until it is dropped, so model updates wait.
            guard lifted == nil, ids != order else { return }
            withAnimation(Self.settle) { order = ids }
        }
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
            reorderableList
        }
    }

    /// Brand book §7.18: positioned rows driven by a `DragGesture`, never a
    /// `List` with `.onMove`.
    ///
    /// `.onMove` runs a system drag session: a translucent snapshot of the row
    /// follows the pointer and an insertion line marks the target, while the
    /// real rows sit still until the drop. Here the grabbed row lifts and every
    /// other row springs to its new slot live, so the drop only confirms what is
    /// already on screen.
    private var reorderableList: some View {
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(orderedBrowsers) { browser in
                        row(browser)
                            .frame(width: geo.size.width)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if height > 0 && abs(height - rowPitch) > 0.5 { rowPitch = height }
                            }
                            .scaleEffect(lifted?.id == browser.id ? 1.03 : 1)
                            .shadow(
                                color: .black.opacity(lifted?.id == browser.id ? 0.45 : 0),
                                radius: lifted?.id == browser.id ? 12 : 0,
                                y: lifted?.id == browser.id ? 6 : 0
                            )
                            .position(x: geo.size.width / 2, y: centerY(of: browser))
                            .zIndex(lifted?.id == browser.id ? 1 : 0)
                            // Animates the lift and, on release, the glide into
                            // the slot. While held the row tracks the pointer.
                            .animation(Self.settle, value: lifted?.id == browser.id)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
                                    .onChanged { drag(browser, $0) }
                                    .onEnded { _ in drop() }
                            )
                            .accessibilityAction(named: "Move Up") { move(browser, by: -1) }
                            .accessibilityAction(named: "Move Down") { move(browser, by: 1) }
                    }
                }
                .frame(
                    width: geo.size.width,
                    height: CGFloat(orderedBrowsers.count) * rowPitch + Self.gap
                )
                .coordinateSpace(name: Self.space)
            }
        }
        .frame(maxHeight: .infinity)
        // The rows' content is aligned with everything else in the window; it is
        // the fill behind it that is wider. Without this the row would have to
        // choose between a fill flush to its content and content indented past
        // the heading, and it used to pick the second.
        .padding(.horizontal, -Self.fillInset)
    }

    private func row(_ browser: Browser) -> some View {
        let isDefault = store.isDefault(browser)

        return HStack(spacing: 10) {
            // Brand book §7.18. Not line.3.horizontal: a stock hamburger runs
            // the full width of a column beside the 20pt app icon, where the dot
            // grip is 8.5pt wide and reads as a handle rather than a menu.
            DragGrip()
                .foregroundStyle(Color.gray)
                .help("Drag to reorder")

            // 40pt, the size Imperator MenuBarFolders gives an app icon in its
            // own reorderable app rows. The popover's rows are 20pt because they
            // are a menu bar list; this is a window, and at 20 the artwork was
            // the smallest thing in a row otherwise built around it.
            Image(nsImage: browser.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)

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
                .opacity(store.isSwitching ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.2), value: store.isSwitching)
                .help("Make \(browser.name) the default browser")
            }
        }
        // Inner padding. Brand book §7.5: H 8, V 4-6.
        .padding(.horizontal, Self.fillInset)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No hover fill on these rows. The popover's rows light up because a
        // click there switches the default browser; here a click does nothing,
        // the row is a drag handle, and the DEFAULT capsule already says which
        // one is current.
        //
        // Outer padding: vertical only. A horizontal inset would push the
        // content off the window margin, which is what this layout is arranged
        // to hold.
        .padding(.vertical, Self.gap / 2)
        // Hit testing last, so the whole padded row is the drag target rather
        // than only the area the labels cover.
        .contentShape(Rectangle())
    }

    // MARK: - Reordering

    /// The store's browsers in `order`. Anything the order has not seen yet, a
    /// browser installed since the window opened, keeps its discovery position
    /// at the end rather than disappearing.
    private var orderedBrowsers: [Browser] {
        let byID = Dictionary(store.browsers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [Browser] = []
        for id in order {
            if let browser = byID[id], seen.insert(id).inserted { result.append(browser) }
        }
        for browser in store.browsers where seen.insert(browser.id).inserted { result.append(browser) }
        return result
    }

    private func centerY(of browser: Browser) -> CGFloat {
        if let lifted, lifted.id == browser.id {
            return lifted.pointerY - lifted.grab
        }
        let index = order.firstIndex(of: browser.id) ?? order.count
        return Self.gap / 2 + (CGFloat(index) + 0.5) * rowPitch
    }

    private func drag(_ browser: Browser, _ value: DragGesture.Value) {
        if lifted == nil {
            lifted = LiftedRow(
                id: browser.id,
                pointerY: value.startLocation.y,
                grab: value.startLocation.y - centerY(of: browser),
                startOrder: order
            )
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        guard var current = lifted, current.id == browser.id else { return }
        current.pointerY = value.location.y
        lifted = current

        let rowCenter = current.pointerY - current.grab
        let slot = Int(((rowCenter - Self.gap / 2) / rowPitch).rounded(.down))
        let target = min(max(slot, 0), order.count - 1)
        if let from = order.firstIndex(of: browser.id), from != target {
            withAnimation(Self.settle) {
                order.remove(at: from)
                order.insert(browser.id, at: target)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// One write per drop, and only when the order actually changed. A drag
    /// across five slots saves once, not five times.
    private func drop() {
        guard let current = lifted else { return }
        withAnimation(Self.settle) { lifted = nil }
        guard order != current.startOrder else { return }
        commitOrder()
    }

    /// Brand book §7.18: a row only a pointer can move is a control half
    /// finished. The `List` this replaced had no keyboard path either.
    private func move(_ browser: Browser, by step: Int) {
        guard let from = order.firstIndex(of: browser.id) else { return }
        let to = min(max(from + step, 0), order.count - 1)
        guard to != from else { return }
        withAnimation(Self.settle) {
            order.remove(at: from)
            order.insert(browser.id, at: to)
        }
        commitOrder()
    }

    private func commitOrder() {
        let byID = Dictionary(store.browsers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        store.reorder(to: order.compactMap { byID[$0] })
    }
}
