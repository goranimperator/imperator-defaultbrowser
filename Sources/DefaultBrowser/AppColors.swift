import SwiftUI
import AppKit

/// Brand book §2.6. Never use bare `Color.accentColor` anywhere in this app --
/// it falls back to the macOS system accent, which may be blue.
enum AppColors {
    static let brand = Color(red: 0xa0/255.0, green: 0x18/255.0, blue: 0x18/255.0)
    static let brandFaded = brand.opacity(0.25)
    static let accent = Color(red: 0.43, green: 0.05, blue: 0.05)
    static let error = Color(red: 0.9, green: 0.3, blue: 0.3)

    static let brandNS = NSColor(red: 0xa0/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
    static let backgroundNS = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
}
