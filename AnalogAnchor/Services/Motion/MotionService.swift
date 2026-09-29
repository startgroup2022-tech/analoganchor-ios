import Foundation
import CoreMotion
import AnalogAnchorKit

/// CoreMotion wrapper for the two motion behaviours the app genuinely uses:
///
/// 1. **Step verification** — the Fajr wake proof and the outdoor "Meshwar
///    Al-Sakeenah" walks both count steps. `CMPedometer` is used for historical
///    counts and `CMPedometer` live updates for the active wake challenge.
/// 2. **Face-down invariant** — the Thinking-on-Paper ritual monitors device
///    attitude to detect the phone being picked up or flipped over.
///
/// Requires `NSMotionUsageDescription` (added to Info.plist) and, for the step
/// APIs, the user's Motion & Fitness permission.
@MainActor
final class MotionService: ObservableObject {

    @Published private(set) var isPedometerAvailable: Bool
    @Published private(set) var liveStepCount: Int = 0
    @Published private(set) var isFaceDown: Bool = false

    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private var stepBaseline: Int?

    init() {
        self.isPedometerAvailable = CMPedometer.isStepCountingAvailable()
    }

    // MARK: - Steps

    /// Counts steps between two dates (e.g. from alarm dismissal to now).
    func steps(from start: Date, to end: Date = Date()) async -> Int {
        guard CMPedometer.isStepCountingAvailable() else { return 0 }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
            }
        }
    }

    /// Begins live step tracking from `start`; updates `liveStepCount`.
    func startLiveStepTracking(from start: Date = Date()) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        liveStepCount = 0
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                self?.liveStepCount = data.numberOfSteps.intValue
            }
        }
    }

    func stopLiveStepTracking() {
        pedometer.stopUpdates()
    }

    /// Convenience for the Fajr wake challenge (mirrors `FAJR_WAKE_STEP_GOAL`).
    var hasMetFajrWakeGoal: Bool {
        liveStepCount >= AnalogAnchorConfig.fajrWakeStepGoal
    }

    // MARK: - Attitude (face-down invariant)

    func startFaceDownMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.5
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            // Gravity z < -0.7 means the screen is facing down (portrait, screen
            // toward the table) — the same intent as the Android Z threshold.
            let faceDown = motion.gravity.z < -0.7
            Task { @MainActor in
                self?.isFaceDown = faceDown
            }
        }
    }

    func stopFaceDownMonitoring() {
        motionManager.stopDeviceMotionUpdates()
        isFaceDown = false
    }

    /// Whether a step detector (as opposed to the pedometer query) is available.
    var isStepCountingAvailable: Bool { isPedometerAvailable }
}

// MARK: - MotionProviding

extension MotionService: MotionProviding {
    /// Domain-facing step query (already matches the protocol signature).
}
