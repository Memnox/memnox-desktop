import Foundation

/// Whether this Mac should be spared work it would feel: little memory, few cores, Low Power Mode or running hot.
enum MachinePace {
    /// At or below these the orb draws fewer frames, since it competes with the agents for the same machine.
    private static let smallMemory: UInt64 = 8 << 30
    private static let fewCores = 4
    /// Low Power Mode and the thermal state change while the app runs, so the answer is read again this often.
    private static let recheck: TimeInterval = 5

    nonisolated(unsafe) private static var checked: (light: Bool, at: Date)?

    /// Read on the main thread only, by the orb and the pointer polls.
    static var light: Bool {
        let now = Date()
        if let checked, now.timeIntervalSince(checked.at) < recheck { return checked.light }
        let info = ProcessInfo.processInfo
        let light = info.physicalMemory <= smallMemory
            || info.activeProcessorCount <= fewCores
            || info.isLowPowerModeEnabled
            || info.thermalState == .serious
            || info.thermalState == .critical
        checked = (light, now)
        return light
    }
}
