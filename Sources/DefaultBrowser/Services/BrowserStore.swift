import AppKit
import Observation

/// The one source of truth for the browser list, the current default, and the
/// order the user dragged them into.
///
/// An Observation type rather than an `ObservableObject`. The practical
/// difference here is the popover: with `@Published` every view that held the
/// store re-rendered on every change, so the row list rebuilt while a switch was
/// only flipping `isSwitching`. Observation tracks the properties a view
/// actually read, so the footer toggle and the row list stop waking each other.
@MainActor
@Observable
final class BrowserStore {
    private(set) var browsers: [Browser] = []
    private(set) var defaultBundleID: String?
    private(set) var isSwitching = false
    var errorMessage: String?

    /// LaunchServices rewrites its handler tables asynchronously, and re-reading the
    /// default right after a successful switch still returns the old browser.
    /// Confirmation therefore polls instead of checking once.
    ///
    /// The delay is not predictable. Measured on macOS 26 it is usually 2 to 4
    /// seconds but has taken over 15, so the window is generous on purpose: giving
    /// up early turns a switch that did land into a false failure banner, which is
    /// worse than a confirmation that arrives late and is never seen.
    private static let confirmationWindow: TimeInterval = 60
    private static let confirmationInterval: TimeInterval = 0.5

    /// Bundle identifiers in the order the user dragged them in Settings. Browsers
    /// missing from this list are newly discovered and keep their discovery order.
    ///
    /// Observed, not `@ObservationIgnored`: `hasCustomOrder` reads it, and the
    /// Reset Order button is bound to that.
    private var customOrder: [String] = BrowserOrderStore.load()

    /// The confirmation poll. Cancelled rather than left to finish when a second
    /// switch starts, so two polls cannot both write `errorMessage`.
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    func refresh() {
        browsers = BrowserOrderStore.apply(customOrder, to: BrowserService.installedBrowsers())
        defaultBundleID = BrowserService.currentDefaultBundleID()
    }

    /// The single place the views ask whether a row is the current default, so the
    /// case-insensitive comparison cannot be forgotten at one of the call sites.
    func isDefault(_ browser: Browser) -> Bool {
        browser.hasBundleID(defaultBundleID)
    }

    // MARK: - Ordering

    /// Commits a reorder from Settings. The view drives the drag itself and calls
    /// this once, on drop, so a drag across five slots is one write rather than
    /// five.
    func reorder(to ordered: [Browser]) {
        guard ordered.map(\.bundleID) != browsers.map(\.bundleID) else { return }
        browsers = ordered
        customOrder = ordered.map(\.bundleID)
        BrowserOrderStore.save(customOrder)
    }

    /// Drops the saved order, which puts the list back in alphabetical order.
    func resetOrder() {
        customOrder = []
        BrowserOrderStore.save([])
        refresh()
    }

    var hasCustomOrder: Bool { !customOrder.isEmpty }

    // MARK: - Switching

    /// `onSuccess` runs as soon as macOS accepts the change, so the popover can close
    /// without waiting for LaunchServices to finish propagating. If the change turns
    /// out not to have taken, the error shows the next time the popover opens.
    func makeDefault(_ browser: Browser, onSuccess: @escaping () -> Void) {
        guard !isSwitching else { return }
        guard !isDefault(browser) else {
            onSuccess()
            return
        }

        confirmationTask?.cancel()
        isSwitching = true
        errorMessage = nil

        // Show the new default now, before the call, not after it. The switch in
        // Settings reads straight from this, and the round trip takes 2 to 4
        // seconds and has been measured over 15, so waiting left the row the
        // user had just switched on sitting visibly off for the whole call: the
        // click read as having done nothing. On failure `refresh()` below puts
        // the real handler back and the banner says what happened.
        defaultBundleID = browser.bundleID

        Task {
            let error = await BrowserService.makeDefault(browser)
            isSwitching = false

            if let error {
                refresh()
                errorMessage = "Could not switch to \(browser.name): \(error.localizedDescription)"
                return
            }

            confirmationTask = Task { await confirm(browser) }
            onSuccess()
        }
    }

    /// Re-reads the default until it is the browser that was just set, or until the
    /// window runs out. A loop rather than a self-rescheduling `DispatchWorkItem`:
    /// the deadline and the give-up message read in order here, and cancelling the
    /// task is what stops it, so a stale poll cannot outlive the switch that
    /// started it.
    private func confirm(_ browser: Browser) async {
        let deadline = Date().addingTimeInterval(Self.confirmationWindow)

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.confirmationInterval))
            guard !Task.isCancelled else { return }

            if browser.hasBundleID(BrowserService.currentDefaultBundleID()) {
                refresh()
                return
            }

            guard Date() < deadline else {
                refresh()
                errorMessage =
                    "\(browser.name) did not become the default browser. Set it in System Settings > Desktop & Dock."
                return
            }
        }
    }
}
