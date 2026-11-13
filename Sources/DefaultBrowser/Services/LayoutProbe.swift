import AppKit
import SwiftUI

/// Headless geometry readout for `--measure-row`, behind `tools/verify-row-layout.mjs`.
///
/// The popover's row geometry used to be checked by eye and written into a
/// manual gate. That missed a real defect for several releases: `scaleEffect`
/// scales what a switch draws but not the box it occupies, so a 0.55 switch
/// kept a full 54x24pt layout box and sat 12.15pt short of the row's trailing
/// padding. Nothing in the source said 12.15, and a screenshot of a translucent
/// menu bar panel is an awkward thing to measure, so it survived review.
///
/// This renders the real `BrowserRow` through `NSHostingView` and reports where
/// the switch actually lands, which makes that class of defect a number a gate
/// can assert on.
///
/// Run it from the bundled binary, not from `.build/release`. AppKit draws the
/// control generation named by the sdk field in LC_BUILD_VERSION, which only
/// `make build` stamps correctly, and the switch is a different size under each:
/// 42x25 at sdk 14.0, 54x24 at sdk 27.2. Measuring the unstamped binary once
/// produced a confident, wrong answer that moved the switch 3.3pt.
@MainActor
enum LayoutProbe {
    /// Row width inside the popover: 340pt panel less the list's 8pt side padding.
    private static let rowWidth = 340 - PopoverContentView.listPadding * 2

    static func measureRow() -> Int32 {
        let browser = Browser(
            bundleID: "com.example.Probe",
            name: "Probe Browser",
            url: URL(fileURLWithPath: "/Applications/Probe.app")
        )

        let row = BrowserRow(browser: browser, isDefault: true, action: {})
            .frame(width: rowWidth)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: rowWidth, height: BrowserRow.height)
        host.layoutSubtreeIfNeeded()

        guard let control = firstSwitch(in: host) else {
            print("no NSSwitch found in the rendered row")
            return 1
        }

        // The switch is drawn scaled, so its own bounds are the unscaled control.
        // What matters is the rectangle it occupies on screen, which is what
        // converting through the host view gives.
        let drawn = control.convert(control.bounds, to: host)

        print("switch bounds (unscaled control): \(fmt(control.bounds.width)) x \(fmt(control.bounds.height))")
        if let parent = control.superview {
            let box = parent.convert(parent.bounds, to: host)
            print("switch layout box: x=\(fmt(box.minX)) w=\(fmt(box.width))")
        }
        print("row width: \(fmt(host.frame.width))")
        print("row height: \(fmt(host.frame.height))")
        print("switch frame: x=\(fmt(drawn.minX)) y=\(fmt(drawn.minY)) w=\(fmt(drawn.width)) h=\(fmt(drawn.height))")
        print("trailing gap: \(fmt(host.frame.width - drawn.maxX))")
        print("leading gap: \(fmt(drawn.minX))")
        // The default row must not be marked with a fill any more: the switch
        // is the only thing that says which browser holds the role. Rendered
        // rather than grepped, because "no background modifier in the source"
        // and "nothing painted behind the row" are different claims.
        let defaultAlpha = backgroundAlpha(isDefault: true, browser: browser)
        let plainAlpha = backgroundAlpha(isDefault: false, browser: browser)
        print("row fill alpha, default row: \(fmt(defaultAlpha))")
        print("row fill alpha, other row: \(fmt(plainAlpha))")

        print("MEASURE_ROW_OK")
        return 0
    }

    /// Alpha painted behind the row, sampled at the vertical middle of the left
    /// padding: inside the row's frame, left of the icon, so only a background
    /// can put anything there. A rounded rectangle fill covers this point; its
    /// 6pt corner radius only cuts the corners.
    private static func backgroundAlpha(isDefault: Bool, browser: Browser) -> CGFloat {
        let row = BrowserRow(browser: browser, isDefault: isDefault, action: {})
            .frame(width: rowWidth)
        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: rowWidth, height: BrowserRow.height)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        // Transparent to start with, so anything non-zero was painted by the row.
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)

        let x = Int(4 * (rep.pixelsWide / Int(host.bounds.width.rounded())))
        let y = rep.pixelsHigh / 2
        return rep.colorAt(x: x, y: y)?.alphaComponent ?? -1
    }

    /// `Toggle(.switch)` is an `NSSwitch` under SwiftUI, so the tree walk finds
    /// the real control rather than a SwiftUI shape that happens to look like one.
    private static func firstSwitch(in view: NSView) -> NSView? {
        if view is NSSwitch { return view }
        for subview in view.subviews {
            if let found = firstSwitch(in: subview) { return found }
        }
        return nil
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
