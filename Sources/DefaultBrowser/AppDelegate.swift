import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hostingController: NSHostingController<AnyView>!
    private var store: BrowserStore!
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Brand book §15.2: the name appears in the process list too.
        ProcessInfo.processInfo.setValue("Imperator DefaultBrowser", forKey: "processName")

        store = BrowserStore()
        store.refresh()

        setupStatusItem()
        setupPopover()
        setupMainMenu()
        observeStore()

        // Handy for a fresh install and for scripted checks: open straight into
        // Settings instead of making the user find the status item first.
        if CommandLine.arguments.contains("--settings") {
            showSettingsWindow()
        }

        // Brand book §6.1: close the popover on any click outside it.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A click on our own status item is already handled by the button's
                // action. Closing here too races with the toggle and can swallow the
                // open, so leave that click alone.
                if let statusWindow = self.statusItem.button?.window,
                   NSMouseInRect(NSEvent.mouseLocation, statusWindow.frame, false) {
                    return
                }
                self.closePopover()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = GlobeIcon.statusBarImage(size: 14)
        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "Switch the default web browser"
    }

    private func setupPopover() {
        let contentView = PopoverContentView(
            onSwitched: { [weak self] in
                MainActor.assumeIsolated { self?.closePopover() }
            },
            onOpenSettings: { [weak self] in
                MainActor.assumeIsolated {
                    self?.closePopover()
                    self?.showSettingsWindow()
                }
            }
        )
        .environmentObject(store)

        hostingController = NSHostingController(rootView: AnyView(contentView))

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        updatePopoverSize()
    }

    /// Brand book §5.1: 340pt wide, height driven by the content. The height is
    /// computed the same way MenuBarFolders computes its grid popover instead of
    /// being left to SwiftUI, so the popover never opens clipped.
    private func updatePopoverSize() {
        let height = PopoverContentView.totalHeight(
            browserCount: store.browsers.count,
            hasError: store.errorMessage != nil
        )
        let size = NSSize(width: 340, height: height)
        hostingController.preferredContentSize = size
        popover.contentSize = size
    }

    private func observeStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePopoverSize() }
            }
            .store(in: &cancellables)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Brand book §15.2: Quit carries the full app name and Cmd+Q.
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Imperator DefaultBrowser",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Imperator DefaultBrowser",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Actions

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func showSettings() {
        showSettingsWindow()
    }

    /// Brand book §6.4. The settings window owns the rescan button and the browser
    /// order; the popover stays a one-click switcher.
    private func showSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        store.refresh()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.windowSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Imperator DefaultBrowser"
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(store))
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // The default handler can change from System Settings or from a browser's own
        // prompt while this app sits idle, so rescan every time the popover opens.
        store.refresh()
        updatePopoverSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}
