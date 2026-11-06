import SwiftUI
import ServiceManagement

/// Brand book §7.1.
struct HoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .opacity(isHovered ? 1.0 : 0.45)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Brand book §7.2. The app's switch, drawn once so the row switch and the
/// footer switch cannot drift apart.
///
/// The frame is the point of this type. `scaleEffect` scales what is drawn and
/// leaves the layout box alone, so without a frame the switch keeps a layout box
/// far wider than its drawing and sits short of the trailing padding of every
/// row that holds one.
///
/// The size below is the control the shipped binary renders, read off the live
/// view tree by `--measure-row`.
///
/// Measure it on a binary built by `make build`, never on a plain
/// `swift build` one. AppKit picks a control's generation from the sdk field in
/// LC_BUILD_VERSION, and SwiftPM stamps that with the deployment target, so the
/// same Toggle is 42x25 under an sdk 14.0 stamp and 54x24 under the sdk 27.2 the
/// Makefile stamps. 54x24 is what ships. `tools/verify-row-layout.mjs` measures
/// the bundled binary and refuses an unstamped one for exactly this reason.
struct BrandSwitch: View {
    @Binding var isOn: Bool

    /// The rendered control's size under the shipped sdk 27 stamp, from
    /// `--measure-row` on the bundled binary.
    static let unscaled = CGSize(width: 54, height: 24)
    static let scale: CGFloat = 0.55
    static var size: CGSize {
        CGSize(width: unscaled.width * scale, height: unscaled.height * scale)
    }

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .scaleEffect(Self.scale)
            .tint(AppColors.brand)
            .labelsHidden()
            .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// Brand book §7.2. Sits on the left of every popover footer.
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Open at Login")
                .font(.caption)
            BrandSwitch(isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        isEnabled = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .opacity(isHovered ? 1.0 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
