import Foundation
import IOKit
import Darwin

/// Force Touch actuator via MultitouchSupport (private API).
/// Use for Developer ID / direct distribution only — not Mac App Store.
final class MultitouchHapticEngine: HapticEngine {
    private static let lock = NSLock()
    private static var actuator: CFTypeRef?
    private static var deviceID: UInt64 = 0
    private static var symbolsLoaded = false

    private static var createFromDeviceID: (@convention(c) (UInt64) -> CFTypeRef?)?
    private static var open: (@convention(c) (CFTypeRef) -> IOReturn)?
    private static var close: (@convention(c) (CFTypeRef) -> IOReturn)?
    private static var actuate: (@convention(c) (CFTypeRef, Int32, UInt32, Float32, Float32) -> IOReturn)?

    static var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        loadSymbolsIfNeeded()
        openActuatorIfNeeded()
        return actuator != nil
    }

    @discardableResult
    func play(intensity: HapticIntensity) -> Bool {
        Self.click(actuationID: Int32(intensity.rawValue), gain: 2.0)
    }

    @discardableResult
    static func click(actuationID: Int32, gain: Float = 2.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        loadSymbolsIfNeeded()
        openActuatorIfNeeded()

        if actuateOnce(actuationID, gain: gain) {
            return true
        }
        closeActuator()
        openActuatorIfNeeded()
        return actuateOnce(actuationID, gain: gain)
    }

    private static func loadSymbolsIfNeeded() {
        guard !symbolsLoaded else { return }
        symbolsLoaded = true

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/Current/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }

        createFromDeviceID = unsafeBitCast(
            dlsym(handle, "MTActuatorCreateFromDeviceID"),
            to: (@convention(c) (UInt64) -> CFTypeRef?)?.self
        )
        open = unsafeBitCast(dlsym(handle, "MTActuatorOpen"), to: (@convention(c) (CFTypeRef) -> IOReturn)?.self)
        close = unsafeBitCast(dlsym(handle, "MTActuatorClose"), to: (@convention(c) (CFTypeRef) -> IOReturn)?.self)
        actuate = unsafeBitCast(
            dlsym(handle, "MTActuatorActuate"),
            to: (@convention(c) (CFTypeRef, Int32, UInt32, Float32, Float32) -> IOReturn)?.self
        )
    }

    private static func openActuatorIfNeeded() {
        guard actuator == nil else { return }
        guard let createFromDeviceID, let open else { return }

        if deviceID == 0 {
            deviceID = findBuiltInTrackpadMultitouchID()
        }
        guard deviceID != 0, let ref = createFromDeviceID(deviceID) else { return }
        guard open(ref) == kIOReturnSuccess else { return }
        actuator = ref
    }

    private static func closeActuator() {
        if let actuator, let close {
            _ = close(actuator)
        }
        actuator = nil
    }

    private static func actuateOnce(_ actuationID: Int32, gain: Float) -> Bool {
        guard let actuator, let actuate else { return false }
        return actuate(actuator, actuationID, 0, 0.0, gain) == kIOReturnSuccess
    }

    private static func findBuiltInTrackpadMultitouchID() -> UInt64 {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleMultitouchDevice") else { return 0 }
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var propertiesRef: Unmanaged<CFMutableDictionary>?
            let propsKR = IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
            guard propsKR == KERN_SUCCESS,
                  let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let actuationSupported = (properties["ActuationSupported"] as? Bool) ?? false
            let builtIn = (properties["MT Built-In"] as? Bool) ?? false
            guard actuationSupported, builtIn else { continue }

            if let id = properties["Multitouch ID"] as? NSNumber {
                return id.uint64Value
            }
        }
        return 0
    }
}
