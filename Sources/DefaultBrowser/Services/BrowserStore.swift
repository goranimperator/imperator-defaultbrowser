import AppKit
import Combine

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var browsers: [Browser] = []
    @Published private(set) var defaultBundleID: String?
    @Published private(set) var isSwitching = false
    @Published var errorMessage: String?

    /// LaunchServices rewrites its handler tables asynchronously, and re-reading the
    /// default right after a successful switch still returns the old browser for a
    /// couple of seconds. Confirmation therefore polls instead of checking once.
    private static let confirmationAttempts = 24
    private static let confirmationInterval: TimeInterval = 0.4

    /// Bundle identifiers in the order the user dragged them in Settings. Browsers
    /// missing from this list are newly discovered and keep their discovery order.
    private var customOrder: [String] = BrowserOrderStore.load()

    private var confirmationWorkItem: DispatchWorkItem?

    func refresh() {
        browsers = BrowserOrderStore.apply(customOrder, to: BrowserService.installedBrowsers())
        defaultBundleID = BrowserService.currentDefaultBundleID()
    }

    // MARK: - Ordering

    /// Moves rows in Settings and persists the result.
    func move(from source: IndexSet, to destination: Int) {
        var reordered = browsers
        reordered.move(fromOffsets: source, toOffset: destination)
        browsers = reordered
        customOrder = reordered.map(\.bundleID)
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
        guard browser.bundleID != defaultBundleID else {
            onSuccess()
            return
        }

        confirmationWorkItem?.cancel()
        isSwitching = true
        errorMessage = nil

        BrowserService.makeDefault(browser) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSwitching = false

                if let error {
                    self.refresh()
                    self.errorMessage = "Could not switch to \(browser.name): \(error.localizedDescription)"
                    return
                }

                // macOS accepted the change, so show it straight away and verify in
                // the background rather than making the user watch a spinner.
                self.defaultBundleID = browser.bundleID
                self.scheduleConfirmation(of: browser, attemptsLeft: Self.confirmationAttempts)
                onSuccess()
            }
        }
    }

    private func scheduleConfirmation(of browser: Browser, attemptsLeft: Int) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                if BrowserService.currentDefaultBundleID() == browser.bundleID {
                    self.refresh()
                    return
                }

                guard attemptsLeft > 1 else {
                    self.refresh()
                    self.errorMessage =
                        "\(browser.name) did not become the default browser. Set it in System Settings > Desktop & Dock."
                    return
                }

                self.scheduleConfirmation(of: browser, attemptsLeft: attemptsLeft - 1)
            }
        }

        confirmationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationInterval, execute: work)
    }
}
