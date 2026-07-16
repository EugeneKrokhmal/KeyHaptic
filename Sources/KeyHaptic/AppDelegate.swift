import AppKit
import ApplicationServices

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var monitor: KeyboardHapticMonitor!
    private var statusItem: NSStatusItem!
    private var preferences: PreferencesController!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        _ = Unmanaged.passRetained(delegate)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = KeyboardHapticMonitor()
        preferences = PreferencesController(monitor: monitor)
        monitor.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusIcon()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = statusBarImage(listening: false)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyUpOrDown

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
        monitor.start()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func statusBarImage(listening: Bool) -> NSImage {
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            let img = image.copy() as! NSImage
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        let name = listening ? "hand.tap.fill" : "hand.raised.slash"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "KeyHaptic")!
        image.isTemplate = true
        return image
    }

    private func updateStatusIcon() {
        statusItem.button?.image = statusBarImage(listening: monitor.isListening && monitor.hasInputAccess)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: monitor.isEnabled ? "Haptics: On" : "Haptics: Off",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let scrollToggle = NSMenuItem(
            title: monitor.scrollEnabled ? "Picker scroll: On" : "Picker scroll: Off",
            action: #selector(toggleScroll),
            keyEquivalent: ""
        )
        scrollToggle.target = self
        menu.addItem(scrollToggle)

        menu.addItem(NSMenuItem.separator())

        let prefs = NSMenuItem(title: "Intensities…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let lengthMenu = NSMenu()
        for (title, value) in [("Short (1)", 1), ("Medium (3)", 3), ("Long (6)", 6), ("Extra (10)", 10)] {
            let item = NSMenuItem(title: title, action: #selector(setPulses(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = monitor.pulses == value ? .on : .off
            lengthMenu.addItem(item)
        }
        let lengthItem = NSMenuItem(title: "Key length", action: nil, keyEquivalent: "")
        lengthItem.submenu = lengthMenu
        menu.addItem(lengthItem)

        let frequencyMenu = NSMenu()
        for (title, value) in [("Slow (40ms)", 40), ("Medium (20ms)", 20), ("Fast (12ms)", 12), ("Rapid (8ms)", 8)] {
            let item = NSMenuItem(title: title, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = monitor.intervalMs == value ? .on : .off
            frequencyMenu.addItem(item)
        }
        let frequencyItem = NSMenuItem(title: "Key frequency", action: nil, keyEquivalent: "")
        frequencyItem.submenu = frequencyMenu
        menu.addItem(frequencyItem)

        menu.addItem(NSMenuItem.separator())

        let test = NSMenuItem(title: "Test haptic", action: #selector(testHaptic), keyEquivalent: "")
        test.target = self
        menu.addItem(test)

        let status = NSMenuItem(title: monitor.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !monitor.hasInputAccess || !monitor.isListening {
            menu.addItem(NSMenuItem.separator())
            let perm = NSMenuItem(
                title: "Open Input Monitoring…",
                action: #selector(openPermissions),
                keyEquivalent: ""
            )
            perm.target = self
            menu.addItem(perm)
        }

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit KeyHaptic", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        updateStatusIcon()
    }

    @objc private func toggleEnabled() {
        monitor.isEnabled.toggle()
        if monitor.isEnabled {
            monitor.start()
        }
    }

    @objc private func toggleScroll() {
        monitor.scrollEnabled.toggle()
    }

    @objc private func openPreferences() {
        preferences.show()
    }

    @objc private func setPulses(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        monitor.pulses = value
        monitor.playCurrentPattern()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        monitor.intervalMs = value
        monitor.playCurrentPattern()
    }

    @objc private func testHaptic() {
        monitor.playCurrentPattern()
    }

    @objc private func openPermissions() {
        monitor.openInputMonitoringSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
