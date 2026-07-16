import AppKit

final class PublicHapticEngine: HapticEngine {
    @discardableResult
    func play(intensity: HapticIntensity) -> Bool {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch intensity {
        case .soft, .light:
            pattern = .alignment
        case .weak, .medium:
            pattern = .levelChange
        case .firm, .strong:
            pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        return true
    }
}
