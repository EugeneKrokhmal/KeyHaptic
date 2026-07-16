import AppKit

final class PreferencesController: NSObject {
    private let monitor: KeyboardHapticMonitor
    private var window: NSWindow?

    private var keyLabel: NSTextField!
    private var scrollLabel: NSTextField!
    private var notchLabel: NSTextField!

    init(monitor: KeyboardHapticMonitor) {
        self.monitor = monitor
        super.init()
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refreshLabels()
    }

    private func makeWindow() -> NSWindow {
        let width: CGFloat = 320
        let height: CGFloat = 220
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyHaptic"
        window.isFloatingPanel = true
        window.level = .floating
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = content

        var y = height - 36

        keyLabel = addCaption("Key intensity", in: content, y: y)
        y -= 28
        let keySlider = addSlider(
            in: content,
            y: y,
            min: 1,
            max: 6,
            value: Double(monitor.strength.rawValue),
            action: #selector(keyIntensityChanged(_:))
        )
        keySlider.numberOfTickMarks = 6
        keySlider.allowsTickMarkValuesOnly = true

        y -= 40
        scrollLabel = addCaption("Scroll intensity", in: content, y: y)
        y -= 28
        let scrollSlider = addSlider(
            in: content,
            y: y,
            min: 1,
            max: 6,
            value: Double(monitor.scrollStrength.rawValue),
            action: #selector(scrollIntensityChanged(_:))
        )
        scrollSlider.numberOfTickMarks = 6
        scrollSlider.allowsTickMarkValuesOnly = true

        y -= 40
        notchLabel = addCaption("Picker notch", in: content, y: y)
        y -= 28
        _ = addSlider(
            in: content,
            y: y,
            min: 6,
            max: 24,
            value: monitor.scrollTickDistance,
            action: #selector(notchChanged(_:))
        )

        return window
    }

    private func addCaption(_ text: String, in parent: NSView, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 20, y: y, width: 280, height: 18)
        parent.addSubview(label)
        return label
    }

    private func addSlider(
        in parent: NSView,
        y: CGFloat,
        min: Double,
        max: Double,
        value: Double,
        action: Selector
    ) -> NSSlider {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.frame = NSRect(x: 20, y: y, width: 280, height: 24)
        slider.isContinuous = true
        parent.addSubview(slider)
        return slider
    }

    private func refreshLabels() {
        keyLabel?.stringValue = "Key intensity — \(monitor.strength.title)"
        scrollLabel?.stringValue = "Scroll intensity — \(monitor.scrollStrength.title)"
        notchLabel?.stringValue = String(format: "Picker notch — %.0f pt", monitor.scrollTickDistance)
    }

    @objc private func keyIntensityChanged(_ sender: NSSlider) {
        let raw = Int(sender.doubleValue.rounded())
        guard let strength = HapticIntensity(rawValue: raw) else { return }
        monitor.strength = strength
        refreshLabels()
        monitor.playCurrentPattern()
    }

    @objc private func scrollIntensityChanged(_ sender: NSSlider) {
        let raw = Int(sender.doubleValue.rounded())
        guard let strength = HapticIntensity(rawValue: raw) else { return }
        monitor.scrollStrength = strength
        refreshLabels()
        monitor.playScrollPreview()
    }

    @objc private func notchChanged(_ sender: NSSlider) {
        monitor.scrollTickDistance = sender.doubleValue
        refreshLabels()
    }
}
