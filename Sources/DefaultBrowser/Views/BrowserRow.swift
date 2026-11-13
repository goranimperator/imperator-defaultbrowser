import SwiftUI

/// One installed browser, one row.
///
/// The switch is the only thing that marks the default browser. No fill behind
/// the active row and no hover fill: the row carried a brand red background and
/// a red-tinted hover, which put three different signals on one list. The switch
/// says which browser holds the http and https roles, the same way the Settings
/// window's rows do.
struct BrowserRow: View {
    let browser: Browser
    let isDefault: Bool
    let action: () -> Void

    static let height: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: browser.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)

            // Brand book §7.5: .regular when inactive, .medium when active. That
            // weight is the only thing beside the switch that separates the two,
            // and it is deliberately quiet.
            Text(browser.name)
                .font(.system(size: 13, weight: isDefault ? .medium : .regular))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            indicator
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .expandTapTarget()
        .onTapGesture(perform: action)
        .help(isDefault ? "\(browser.name) is the default browser" : "Make \(browser.name) the default browser")
    }

    /// Brand book §7.2: the system switch, the same control the footer and the
    /// Settings rows use, not a drawn lookalike.
    ///
    /// It never takes a click of its own here. The row is the control, which
    /// rules out the one gesture a live toggle would invite and the system
    /// cannot honour: switching the default browser off. macOS always has one.
    private var indicator: some View {
        BrandSwitch(label: browser.name, isOn: .constant(isDefault))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
