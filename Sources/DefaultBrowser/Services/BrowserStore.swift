import AppKit
import Combine

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var browsers: [Browser] = []
    @Published private(set) var defaultBundleID: String?
    @Published private(set) var isSwitching = false
    @Published var errorMessage: String?

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
    private var customOrder: [String] = BrowserOrderStore.load()

    private var confirmationWorkItem: DispatchWorkItem?

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
        guard !isDefault(browser) else {
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
                self.scheduleConfirmation(
                    of: browser,
                    giveUpAt: Date().addingTimeInterval(Self.confirmationWindow)
                )
                onSuccess()
            }
        }
    }

    private func scheduleConfirmation(of browser: Browser, giveUpAt deadline: Date) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                if browser.hasBundleID(BrowserService.currentDefaultBundleID()) {
                    self.confirmationWorkItem = nil
                    self.refresh()
                    return
                }

                guard Date() < deadline else {
                    self.confirmationWorkItem = nil
                    self.refresh()
                    self.errorMessage =
                        "\(browser.name) did not become the default browser. Set it in System Settings > Desktop & Dock."
                    return
                }

                self.scheduleConfirmation(of: browser, giveUpAt: deadline)
            }
        }

        confirmationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationInterval, execute: work)
    }
}
