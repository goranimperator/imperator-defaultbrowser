import SwiftUI

/// Brand book §7.18. Lucide `grip-vertical`, two columns of three dots: the
/// affordance at the left of a row the user can drag to reorder.
///
/// The sizes are half-points, not the 3.33pt and 1.67pt that Lucide's 24-unit
/// box gives at 20pt. A fraction like that falls between device pixels, and each
/// dot rounds by where it happens to land, so they come out visibly unequal.
/// Half-points are exact at 2x: 7px dots, 3px between columns, 5px between rows.
///
/// Drawn rather than added to the app's Lucide set. `SVGRenderer` could render
/// it, but the brand book draws this one glyph from shapes on purpose, and the
/// six dots are cheaper as circles than as a parsed path.
///
/// The grip is the affordance only. The drag is the row's own `DragGesture`, so
/// the whole row is the target rather than these 8.5 points of it.
///
/// No hover state. Brand book §7.18 still describes a `.tertiary` to
/// `Color.gray` crossfade driven by the row's hover, but that rule is out of
/// date: the grip sits at the hovered weight, `Color.gray`, all the time. A grip
/// that is only legible once the pointer is already on the row advertises the
/// drag to someone who has found it anyway.
///
/// The colour is the caller's, set with `foregroundStyle`, the same as
/// Imperator MenuBarFolders.
struct DragGrip: View {
    private static let dot: CGFloat = 3.5
    private static let columnGap: CGFloat = 1.5
    private static let rowGap: CGFloat = 2.5

    /// Three dots and the two gaps between them. The row's other glyphs match
    /// this so they read as one set.
    static let height: CGFloat = dot * 3 + rowGap * 2

    var body: some View {
        VStack(spacing: Self.rowGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: Self.columnGap) {
                    Circle().frame(width: Self.dot, height: Self.dot)
                    Circle().frame(width: Self.dot, height: Self.dot)
                }
            }
        }
    }
}
