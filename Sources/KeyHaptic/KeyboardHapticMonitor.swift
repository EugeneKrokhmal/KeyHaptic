import AppKit
import ApplicationServices
import Foundation

final class KeyboardHapticMonitor {
    var isEnabled = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "hapticEnabled") }
    }
    var scrollEnabled = true {
        didSet { UserDefaults.standard.set(scrollEnabled, forKey: "scrollHapticEnabled") }
    }
    var strength: HapticIntensity {
        didSet { UserDefaults.standard.set(strength.rawValue, forKey: "hapticStrength") }
    }
    var pulses: Int {
        didSet { UserDefaults.standard.set(pulses, forKey: "hapticPulses") }
    }
    var intervalMs: Int {
        didSet { UserDefaults.standard.set(intervalMs, forKey: "hapticIntervalMs") }
    }
    var scrollTickDistance: Double {
        didSet { UserDefaults.standard.set(scrollTickDistance, forKey: "scrollTickDistance") }
    }
    var scrollStrength: HapticIntensity {
        didSet { UserDefaults.standard.set(scrollStrength.rawValue, forKey: "scrollStrength") }
    }

    private(set) var hasInputAccess = false
    private(set) var hasAccessibility = false
    private(set) var isListening = false
    private(set) var keyCount = 0
    private(set) var scrollTickCount = 0

    var onChange: (() -> Void)?

    var statusText: String {
        if keyCount > 0 || scrollTickCount > 0 {
            return "Keys \(keyCount) · Scroll \(scrollTickCount)"
        }
        if isListening {
            return "Listening — type or scroll"
        }
        return "Grant Input Monitoring, then Quit & Reopen"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalKeyMonitor: Any?
    private var globalScrollMonitor: Any?
    private var pollTimer: Timer?
    private var lastKeyActuation = Date.distantPast
    private var lastScrollActuation = Date.distantPast
    private var lastEventAt = Date()
    private var scrollAccumulator: Double = 0
    private var isFingerScrolling = false
    private let stateLock = NSLock()
    private let engine = HapticEngineFactory.make()
    private let hapticQueue = DispatchQueue(label: "com.keyhaptic.haptic", qos: .userInteractive)

    private let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("KeyHaptic.log")
    }()

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hapticEnabled") != nil {
            isEnabled = defaults.bool(forKey: "hapticEnabled")
        }
        if defaults.object(forKey: "scrollHapticEnabled") != nil {
            scrollEnabled = defaults.bool(forKey: "scrollHapticEnabled")
        }
        let savedStrength = defaults.integer(forKey: "hapticStrength")
        strength = HapticIntensity(rawValue: savedStrength) ?? .strong
        pulses = (defaults.object(forKey: "hapticPulses") as? Int) ?? 1
        intervalMs = (defaults.object(forKey: "hapticIntervalMs") as? Int) ?? 20
        scrollTickDistance = (defaults.object(forKey: "scrollTickDistance") as? Double) ?? 10
        let savedScrollStrength = defaults.integer(forKey: "scrollStrength")
        scrollStrength = HapticIntensity(rawValue: savedScrollStrength) ?? .light
    }

    func start() {
        log("start pid=\(ProcessInfo.processInfo.processIdentifier)")
        _ = CGRequestListenEventAccess()
        let axOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(axOptions)

        installListeners()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.maintainListeners()
        }
    }

    func openInputMonitoringSettings() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func playCurrentPattern() {
        let level = strength
        let count = max(1, min(pulses, 6)) // cap so the queue can't stall
        let gapMs = max(1, intervalMs)

        hapticQueue.async {
            for i in 0..<count {
                if i > 0 { usleep(useconds_t(gapMs * 1000)) }
                _ = self.engine.play(intensity: level)
            }
        }
    }

    func playScrollPreview() {
        playScrollTick()
    }

    private func playScrollTick() {
        let level = scrollStrength
        hapticQueue.async {
            _ = self.engine.play(intensity: level)
        }
    }

    private func maintainListeners() {
        hasInputAccess = CGPreflightListenEventAccess()
        hasAccessibility = AXIsProcessTrusted()

        stateLock.lock()
        if isFingerScrolling, Date().timeIntervalSince(lastEventAt) > 0.35 {
            isFingerScrolling = false
            scrollAccumulator = 0
        }
        stateLock.unlock()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }

        if isEnabled, eventTap == nil, globalKeyMonitor == nil {
            installListeners()
            return
        }

        let quiet = Date().timeIntervalSince(lastEventAt) > 30
        if isEnabled, hasInputAccess, quiet, eventTap != nil, keyCount == 0, scrollTickCount == 0 {
        }

        isListening = eventTap != nil || globalKeyMonitor != nil
        onChange?()
    }

    private func tearDownListeners() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let globalScrollMonitor { NSEvent.removeMonitor(globalScrollMonitor) }
        eventTap = nil
        runLoopSource = nil
        globalKeyMonitor = nil
        globalScrollMonitor = nil
        isListening = false
    }

    private func installListeners() {
        guard isEnabled else {
            isListening = false
            onChange?()
            return
        }

        hasInputAccess = CGPreflightListenEventAccess()
        hasAccessibility = AXIsProcessTrusted()

        if eventTap == nil, hasInputAccess {
            eventTap = createTap(at: .cgSessionEventTap) ?? createTap(at: .cghidEventTap)
            if let tap = eventTap {
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                log("event tap installed")
            } else {
                log("event tap create returned nil despite listen=true")
            }
        } else if eventTap != nil, !hasInputAccess {
            log("dropping zombie tap (listen=false)")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }

        if globalKeyMonitor == nil, hasAccessibility {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(isRepeat: event.isARepeat, source: "nsevent")
            }
            log("nsevent key monitor installed")
        }

        if globalScrollMonitor == nil, hasAccessibility {
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(
                    delta: abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX),
                    momentumRaw: event.momentumPhase.rawValue,
                    phaseRaw: event.phase.rawValue,
                    source: "nsevent-scroll"
                )
            }
        }

        let tapOK = eventTap != nil && hasInputAccess
        let nseventOK = globalKeyMonitor != nil && hasAccessibility
        isListening = tapOK || nseventOK
        log("listening=\(isListening) listenPerm=\(hasInputAccess) axPerm=\(hasAccessibility) tap=\(tapOK) nsevent=\(nseventOK)")
        onChange?()
    }

    private func createTap(at location: CGEventTapLocation) -> CFMachPort? {
        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardHapticMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleTap(type: type, event: event)
            },
            userInfo: refcon
        )
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            DispatchQueue.main.async { [weak self] in
                self?.handleKey(isRepeat: isRepeat, source: "tap")
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let lineY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let lineX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            let delta = max(abs(dy) + abs(dx), (abs(lineY) + abs(lineX)) * 8)
            let momentumRaw = UInt(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            let phaseRaw = UInt(event.getIntegerValueField(.scrollWheelEventScrollPhase))

            DispatchQueue.main.async { [weak self] in
                self?.handleScroll(delta: delta, momentumRaw: momentumRaw, phaseRaw: phaseRaw, source: "tap-scroll")
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKey(isRepeat: Bool, source: String) {
        guard isEnabled, !isRepeat else { return }

        stateLock.lock()
        let now = Date()
        let ok = now.timeIntervalSince(lastKeyActuation) >= 0.035
        if ok {
            lastKeyActuation = now
            lastEventAt = now
        }
        stateLock.unlock()
        guard ok else { return }

        playCurrentPattern()
        keyCount += 1
        log("key #\(keyCount) source=\(source)")
        onChange?()
    }

    private func handleScroll(delta: Double, momentumRaw: UInt, phaseRaw: UInt, source: String) {
        guard isEnabled, scrollEnabled else { return }

        let momentum = NSEvent.Phase(rawValue: momentumRaw)
        let phase = NSEvent.Phase(rawValue: phaseRaw)

        let inMomentum =
            momentumRaw != 0 &&
            !momentum.contains(.ended) &&
            !momentum.contains(.cancelled)

        stateLock.lock()
        if phase.contains(.began) || phase.contains(.changed) || phase.contains(.stationary) {
            isFingerScrolling = true
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            isFingerScrolling = false
        }
        if momentum.contains(.ended) || momentum.contains(.cancelled) {
            isFingerScrolling = false
            scrollAccumulator = 0
            stateLock.unlock()
            return
        }
        if phaseRaw == 0, momentumRaw == 0, delta > 0.01 {
            isFingerScrolling = true
        }

        let picking = isFingerScrolling || inMomentum
        if !picking {
            stateLock.unlock()
            return
        }
        if delta <= 0.01 {
            stateLock.unlock()
            return
        }

        lastEventAt = Date()
        scrollAccumulator += delta

        let baseNotch = max(4.0, scrollTickDistance)
        let notch = isFingerScrolling && !inMomentum
            ? max(3.0, baseNotch * 0.55)
            : baseNotch

        var fires = 0
        while scrollAccumulator >= notch && fires < 5 {
            scrollAccumulator -= notch
            let now = Date()
            let minGap = isFingerScrolling && !inMomentum ? 0.012 : 0.016
            if now.timeIntervalSince(lastScrollActuation) >= minGap {
                lastScrollActuation = now
                fires += 1
            } else {
                scrollAccumulator += notch
                break
            }
        }
        stateLock.unlock()

        guard fires > 0 else { return }

        for _ in 0..<fires {
            playScrollTick()
        }

        scrollTickCount += fires
        if scrollTickCount <= fires || scrollTickCount % 25 < fires {
            log("picker #\(scrollTickCount) source=\(source) finger=\(isFingerScrolling) mom=\(inMomentum)")
            onChange?()
        }
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
