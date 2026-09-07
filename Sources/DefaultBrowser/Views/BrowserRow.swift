import SwiftUI

/// Brand book §7.5. One installed browser, one row.
///
/// Every row carries a white indicator circle on the right. The row that is the
/// current default is filled with brand red and its circle holds a red checkmark,
/// so the active browser reads at a glance. Rows have no hover state on purpose --
/// a highlight that follows the pointer down a three-row list reads as a glitch.
struct BrowserRow: View {
    let browser: Browser
    let isDefault: Bool
    let action: () -> Void

    static let height: CGFloat = 32

    private static let indicatorSize: CGFloat = 16

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
        .expandTapTarget()
        .onTapGesture(perform: action)
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
