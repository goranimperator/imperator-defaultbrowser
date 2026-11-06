// The icon path data below is derived from Lucide (https://lucide.dev), icon
// "globe-check".
//
// Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part
// of Feather (MIT). All other copyright (c) for Lucide are held by Lucide
// Contributors 2022. Licensed under the ISC license.
import AppKit

/// The app's glyph: a globe with a check mark. Used for the status bar item and
/// for the popover header.
///
/// Main-actor isolated for the cache below. Every caller is a view or the app
/// delegate, so this costs nothing and is what lets the target build in Swift 6
/// language mode: a plain `static var` is shared mutable state there, and the
/// alternative, a lock around a cache only the main thread ever reaches, would
/// be ceremony around a race that cannot happen.
@MainActor
enum GlobeIcon {
    /// Lucide ships a 24x24 viewBox with stroke-width 2, which SVGRenderer scales.
    private static let elements: [SVGRenderer.Element] = [
        SVGRenderer.Element(kind: .path("m15 6 2 2 4-4"), shouldFill: false),
        SVGRenderer.Element(
            kind: .path("M2 12h20A10 10 0 1 1 12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 4-10"),
            shouldFill: false
        ),
    ]

    private static var cache: [CGFloat: NSImage] = [:]

    /// Template image for the status bar. Brand book §8.1 asks for a template image;
    /// Imperator AirDrop sets its status bar glyph to 14x14pt, and this matches it.
    static func statusBarImage(size: CGFloat = 14) -> NSImage {
        if let cached = cache[size] { return cached }
        let image = SVGRenderer.render(elements: elements, size: size, strokeWidth: 2)
        image.isTemplate = true
        cache[size] = image
        return image
    }
}
