import FoundationModels
import Observation

/// Gates every AI entry point on the on-device model's real availability —
/// never assumed to be present, since Apple Intelligence may be off, the
/// device may be ineligible, or the model may still be downloading.
@MainActor
@Observable
final class AIAvailability {
    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        model.isAvailable
    }

    var unavailableMessage: String? {
        guard case .unavailable(let reason) = model.availability else { return nil }
        switch reason {
        case .deviceNotEligible:
            return "AI suggestions require a device that supports Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use AI trip suggestions."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again shortly."
        @unknown default:
            return "AI suggestions aren't available right now."
        }
    }
}
