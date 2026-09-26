import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel!

    private var store: BrowserStore!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Brand book §15.2: the name appears in the process list too.
        ProcessInfo.processInfo.setValue("Imperator DefaultBrowser", forKey: "processName")

        store = BrowserStore()
        store.refresh()

        setupStatusItem()
        setupPopover()
        setupMainMenu()

        // Handy for a fresh install and for scripted checks: open straight into
        // Settings instead of making the user find the status item first.
        if CommandLine.arguments.contains("--settings") {
            showSettingsWindow()
        }

        // Brand book 6.1's click-outside dismissal lives in MenuBarPanel now,
        // which owns the same monitor and the same exception for the status
        // item's own click. Two monitors closing the same panel raced each
        // other on the toggle.
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

        // A MenuBarPanel rather than an NSPopover. macOS 27 draws its own menu
        // bar panels as plain rounded rectangles: a 17.50 pt corner, no arrow
        // and no animation, measured off Control Centre's Wi-Fi panel. An
        // NSPopover draws none of that and exposes none of it for adjustment.
        panel = MenuBarPanel(content: contentView, width: 340)
        // The height is computed rather than taken from SwiftUI's fitting size,
        // the same way MenuBarFolders computes its grid, so the panel never
        // opens clipped.
        panel.contentHeight = { [weak self] in
            guard let self else { return 0 }
            return PopoverContentView.totalHeight(
                browserCount: self.store.browsers.count,
                hasError: self.store.errorMessage != nil
            )
        }
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
        if panel.isShown {
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
        panel.show(from: button)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        guard panel.isShown else { return }
        panel.close()
    }
}
