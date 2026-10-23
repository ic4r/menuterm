import Darwin
import Foundation

enum Shell {
    /// The user's login shell, falling back to zsh.
    static var path: String {
        let env = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        return env.isEmpty ? "/bin/zsh" : env
    }

    /// Environment handed to child processes, as KEY=VALUE strings.
    static var environment: [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["MENUTERM"] = "1"
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Direct children of `pid` (libproc, no subprocess spawned).
    static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let bytes = Int32(buffer.count * MemoryLayout<pid_t>.size)
        let got = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_listchildpids(pid, ptr.baseAddress, bytes)
        }
        return got > 0 ? Array(buffer.prefix(Int(got))) : []
    }

    /// True when `pid` has at least one live child process.
    static func hasChildren(_ pid: pid_t) -> Bool { !children(of: pid).isEmpty }

    /// `pid` plus every descendant, breadth-first (bounded so a fork bomb cannot stall the poller).
    static func processTree(of pid: pid_t, limit: Int = 512) -> [pid_t] {
        var result: [pid_t] = [pid]
        var i = 0
        while i < result.count, result.count < limit {
            result.append(contentsOf: children(of: result[i]))
            i += 1
        }
        return result
    }

    /// Sends `signal` to the direct children of `pid` (pkill -P), leaving the shell itself
    /// to exit normally so its zshexit hooks can clean up plugin workers.
    static func signalChildren(of pid: pid_t, _ signal: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-\(signal)", "-P", String(pid)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    static func expandTilde(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    // MARK: - Resource usage

    /// One process's cumulative CPU time (ns) and physical memory footprint (bytes),
    /// from proc_pid_rusage — the same source Activity Monitor's "Memory" column uses.
    struct Usage {
        var cpuNanoseconds: UInt64
        var footprintBytes: UInt64
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func usage(of pid: pid_t) -> Usage? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard rc == 0 else { return nil }
        // ri_*_time are in mach absolute time units; convert to nanoseconds.
        let ticks = info.ri_user_time + info.ri_system_time
        let ns = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        return Usage(cpuNanoseconds: ns, footprintBytes: info.ri_phys_footprint)
    }

    /// Human-readable byte count (B/KB/MB/GB, one decimal from MB up).
    static func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        switch b {
        case ..<1024: return "\(bytes) B"
        case ..<(1024 * 1024): return String(format: "%.0f KB", b / 1024)
        case ..<(1024 * 1024 * 1024): return String(format: "%.0f MB", b / (1024 * 1024))
        default: return String(format: "%.1f GB", b / (1024 * 1024 * 1024))
        }
    }
}
