import Foundation

/// Shared intensity levels for both public and private haptic backends.
enum HapticIntensity: Int, CaseIterable, Identifiable {
    case soft = 1
    case light = 2
    case weak = 3
    case medium = 4
    case firm = 5
    case strong = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .soft: return "Soft"
        case .light: return "Light"
        case .weak: return "Weak"
        case .medium: return "Medium"
        case .firm: return "Firm"
        case .strong: return "Strong"
        }
    }
}

protocol HapticEngine {
    @discardableResult
    func play(intensity: HapticIntensity) -> Bool
}

enum HapticEngineFactory {
    static func make() -> HapticEngine {
        #if APPSTORE
        return PublicHapticEngine()
        #else
        // Strong trackpad actuator (not App Store–safe — private MultitouchSupport).
        if MultitouchHapticEngine.isAvailable {
            return MultitouchHapticEngine()
        }
        return PublicHapticEngine()
        #endif
    }
}
