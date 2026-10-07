import Darwin
import os

/// Logs the time from process start to the first rendered frame, the launch metric the
/// shell is budgeted against. Read it with
/// `xcrun simctl spawn booted log stream --predicate 'subsystem == "openGym"'`.
enum LaunchTiming {
    private static let signposter = OSSignposter(subsystem: "openGym", category: "launch")
    private static let logger = Logger(subsystem: "openGym", category: "launch")

    static func firstFrame() {
        signposter.emitEvent("first-frame")
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return }
        let start = info.kp_proc.p_un.__p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        let ms = Double(now.tv_sec - start.tv_sec) * 1000 + Double(now.tv_usec - start.tv_usec) / 1000
        logger.log("first frame \(ms, format: .fixed(precision: 1), privacy: .public) ms after process start")
    }
}
