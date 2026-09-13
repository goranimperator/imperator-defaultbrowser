import SwiftUI

/// Brand book §7.5. One installed browser, one row.
///
/// Every row carries a switch on the right, on for the browser that currently
/// holds the http and https roles. That row is also filled with brand red, so
/// the active browser reads at a glance even at a glance's distance.
///
/// Only the rows that are not the default get a hover fill. The red row is
/// already the loudest thing in the popover and clicking it does nothing, so
/// lighting it up under the pointer would promise an action it does not perform.
struct BrowserRow: View {
    let browser: Browser
    let isDefault: Bool
    let action: () -> Void

    static let height: CGFloat = 32

    /// Faint enough to read as a surface lifting rather than a selection. The
    /// popover sits on a translucent dark ground, so white at 8% is roughly what
    /// an AppKit list uses for the same job in dark mode.
    private static let hoverFill = Color.white.opacity(0.08)
    private static let hoverDuration: TimeInterval = 0.15

    // Switch geometry, matching the scaled Open at Login switch in the footer.
    private static let trackWidth: CGFloat = 28
    private static let trackHeight: CGFloat = 16
    private static let knobInset: CGFloat = 2
    private static let knobTravel = (trackWidth - trackHeight) / 2

    /// The on switch sits on the brand-red row. A red track would hide the
    /// control in its own background, so the track goes dark and the white knob
    /// is what carries the on state.
    private static let onTrack = Color.black.opacity(0.45)
    private static let offTrack = Color.white.opacity(0.22)

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

    /// A switch showing whether this browser holds the http and https roles.
    ///
    /// Drawn rather than built from `Toggle`. An AppKit `NSSwitch` installs its
    /// own cursor rect, which overrides the row's pointing hand and leaves an
    /// arrow sitting over the one control in the row that most looks clickable.
    /// `.allowsHitTesting(false)` does not stop that; the tracking area is below
    /// SwiftUI. Two shapes have no such opinion.
    ///
    /// It shows state and never takes a click of its own. The row is the control,
    /// which also rules out the one gesture a live toggle would invite and the
    /// system cannot honour: switching the default browser off. macOS always has
    /// one. Sized to match the Open at Login switch in the footer, so the app
    /// reads as having one switch rather than two.
    private var indicator: some View {
        ZStack {
            Capsule()
                .fill(isDefault ? Self.onTrack : Self.offTrack)

            Circle()
                .fill(Color.white)
                .padding(Self.knobInset)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .frame(width: Self.trackHeight, height: Self.trackHeight)
                .offset(x: isDefault ? Self.knobTravel : -Self.knobTravel)
        }
        .frame(width: Self.trackWidth, height: Self.trackHeight)
        .animation(.easeInOut(duration: 0.2), value: isDefault)
        .accessibilityHidden(true)
    }
}
