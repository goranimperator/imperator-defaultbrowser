import Foundation

/// Persists the order the user dragged the browsers into, as a list of bundle
/// identifiers. Stored next to where the other Imperator apps keep their state.
enum BrowserOrderStore {
    private static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImperatorDefaultBrowser", isDirectory: true)
    }

    private static var file: URL {
        directory.appendingPathComponent("order.json")
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: file),
              let bundleIDs = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return bundleIDs
    }

    /// Applies a saved order to freshly discovered browsers. Browsers the saved order
    /// has never seen keep their discovery order and land at the end.
    static func apply(_ order: [String], to discovered: [Browser]) -> [Browser] {
        guard !order.isEmpty else { return discovered }

        func rank(of browser: Browser) -> Int {
            order.firstIndex(of: browser.bundleID) ?? order.count
        }

        // Ranking on the index as a tie-break keeps unseen browsers in their
        // discovery order instead of shuffling them on every refresh.
        var ranked: [(rank: Int, index: Int, browser: Browser)] = []
        for (index, browser) in discovered.enumerated() {
            ranked.append((rank: rank(of: browser), index: index, browser: browser))
        }

        ranked.sort { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.index < rhs.index : lhs.rank < rhs.rank
        }

        return ranked.map { $0.browser }
    }

    static func save(_ bundleIDs: [String]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bundleIDs)
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("ImperatorDefaultBrowser: could not save browser order: \(error.localizedDescription)")
        }
    }
}
