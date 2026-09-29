import Foundation
import UIKit

#if canImport(CoreHaptics)
import CoreHaptics
#endif

/// Haptics wrapper.
///
/// The Android app used `Vibrator` with specific waveforms (a strong
/// double-pulse for the Fajr tag, a short tap elsewhere) and a 2X
/// {380ms on, 180ms off} pattern for the Soft Landing signal.
/// This maps those intents onto CoreHaptics / UIFeedbackGenerator so the
/// tactile language is preserved. CoreHaptics is used when available; otherwise
/// the code falls back to the standard feedback generators (never silently
/// no-ops).
@MainActor
final class HapticsService {

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    #endif

    init() {
        prepareEngine()
    }

    private func prepareEngine() {
        #if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()
            self.engine = engine
        } catch {
            // Fall back to UIFeedbackGenerator.
        }
        #endif
    }

    /// Short confirmation tap (non-Fajr tag).
    func tap() {
        #if canImport(CoreHaptics)
        if playTransient(intensity: 0.6, sharpness: 0.8) { return }
        #endif
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Strong double-pulse reserved for the Fajr eraser tag.
    func fajrDoublePulse() {
        #if canImport(CoreHaptics)
        if playPattern(events: [
            (time: 0.0, intensity: 1.0, sharpness: 0.9, duration: 0.35),
            (time: 0.50, intensity: 1.0, sharpness: 0.9, duration: 0.45)
        ]) { return }
        #endif
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// 2X harmonic rhythm used as the Soft Landing tactile signature.
    func softLandingRhythm() {
        #if canImport(CoreHaptics)
        if playPattern(events: [
            (time: 0.0, intensity: 0.8, sharpness: 0.5, duration: 0.38),
            (time: 0.56, intensity: 0.8, sharpness: 0.5, duration: 0.38)
        ]) { return }
        #endif
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    func success() {
        #if canImport(CoreHaptics)
        if playTransient(intensity: 0.9, sharpness: 0.9) { return }
        #endif
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func error() {
        #if canImport(CoreHaptics)
        if playTransient(intensity: 1.0, sharpness: 1.0) { return }
        #endif
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - CoreHaptics helpers

    #if canImport(CoreHaptics)
    @discardableResult
    private func playTransient(intensity: Float, sharpness: Float) -> Bool {
        guard let engine else { return false }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        return play(events: [event], engine: engine)
    }

    @discardableResult
    private func playPattern(events: [(time: TimeInterval, intensity: Float, sharpness: Float, duration: TimeInterval)]) -> Bool {
        guard let engine else { return false }
        let hapticEvents = events.map { spec in
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: spec.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: spec.sharpness)
                ],
                relativeTime: spec.time,
                duration: spec.duration
            )
        }
        return play(events: hapticEvents, engine: engine)
    }

    private func play(events: [CHHapticEvent], engine: CHHapticEngine) -> Bool {
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            return true
        } catch {
            return false
        }
    }
    #endif
}
