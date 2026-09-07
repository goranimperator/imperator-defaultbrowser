import SwiftUI

/// Brand book §7.5. One installed browser, one row.
///
/// Every row carries a white indicator circle on the right. The row that is the
/// current default is filled with brand red and its circle holds a red checkmark,
/// so the active browser reads at a glance.
///
/// Only the rows that are not the default get a hover fill. The red row is
/// already the loudest thing in the popover and clicking it does nothing, so
/// lighting it up under the pointer would promise an action it does not perform.
struct BrowserRow: View {
    let browser: Browser
    let isDefault: Bool
    let action: () -> Void

    static let height: CGFloat = 32

    private static let indicatorSize: CGFloat = 16

    /// Faint enough to read as a surface lifting rather than a selection. The
    /// popover sits on a translucent dark ground, so white at 8% is roughly what
    /// an AppKit list uses for the same job in dark mode.
    private static let hoverFill = Color.white.opacity(0.08)
    private static let hoverDuration: TimeInterval = 0.15

    @State private var isHovered = false

    private var isHighlighted: Bool { isHovered && !isDefault }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: browser.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)

            Text(browser.name)
                .font(.system(size: 13, weight: isDefault ? .medium : .regular))
                .foregroundStyle(isDefault ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            indicator
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDefault ? AppColors.brand : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Self.hoverFill : Color.clear)
        )
        .expandTapTarget()
        .onTapGesture(perform: action)
        // The hover flag is set before .cursor so both react to the same region
        // the tap target covers, not just the row's painted content.
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Self.hoverDuration), value: isHighlighted)
        .cursor(.pointingHand)
        .help(isDefault ? "\(browser.name) is the default browser" : "Make \(browser.name) the default browser")
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: Self.indicatorSize, height: Self.indicatorSize)

            if isDefault {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(AppColors.brand)
            }
        }
        .frame(width: Self.indicatorSize, height: Self.indicatorSize)
    }
}
