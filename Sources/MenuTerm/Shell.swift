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

    /// True when `pid` has at least one live child process (libproc, no subprocess spawned).
    static func hasChildren(_ pid: pid_t) -> Bool {
        var buffer = [pid_t](repeating: 0, count: 64)
        let bytes = Int32(buffer.count * MemoryLayout<pid_t>.size)
        let got = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_listchildpids(pid, ptr.baseAddress, bytes)
        }
        return got > 0
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
}
