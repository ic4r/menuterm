import AppKit
import Darwin
import SwiftTerm

enum SessionState: Equatable {
    /// No shell yet.
    case stopped
    /// Shell is up and the command (or any child) is running.
    case running
    /// Shell is up and sitting at the prompt.
    case idle
    /// Shell exited.
    case exited(Int32?)

    var symbol: String {
        switch self {
        case .stopped: return "○"
        case .running: return "●"
        case .idle: return "◐"
        case .exited: return "✕"
        }
    }

    var label: String {
        switch self {
        case .stopped: return "시작 전"
        case .running: return "실행 중"
        case .idle: return "프롬프트 대기"
        case .exited(let code): return "셸 종료 (code \(code.map(String.init) ?? "signal"))"
        }
    }
}

/// CPU and memory of the shell plus everything under it, sampled once a second.
struct ResourceStats: Equatable {
    /// Percent of one core over the last sampling interval (can exceed 100 on multi-threaded work).
    var cpuPercent: Double
    /// Sum of physical footprints (what Activity Monitor shows as "Memory").
    var memoryBytes: UInt64

    var label: String {
        String(format: "CPU %.0f%%  MEM %@", cpuPercent, Shell.formatBytes(memoryBytes))
    }
}

/// One long-running session: an interactive login shell in a PTY into which the configured
/// command is typed. Running the command inside a real interactive shell keeps .zshrc
/// plugins well-behaved (a `zsh -lic cmd` run leaves their background workers orphaned).
final class Session {
    var config: SessionConfig
    private(set) var state: SessionState = .stopped
    private(set) var stats: ResourceStats?
    private(set) var windowController: TerminalWindowController?
    var onStateChange: ((Session) -> Void)?
    /// Fired after every poll (about once a second) while the shell is alive.
    var onStatsChange: ((Session) -> Void)?

    /// MENUTERM_DEBUG_STATS=1 logs every sample (for checking the numbers without opening the menu).
    private static let debugStats = ProcessInfo.processInfo.environment["MENUTERM_DEBUG_STATS"] == "1"
    private var pollTimer: Timer?
    private var pendingRestart = false
    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastSampleAt: TimeInterval = 0

    init(config: SessionConfig) {
        self.config = config
    }

    var isRunning: Bool { state == .running }
    var shellAlive: Bool { state == .running || state == .idle }

    /// Last `count` non-empty lines visible in the terminal (oldest first), for the menu row.
    func lastLines(_ count: Int) -> [String] {
        guard let view = windowController?.terminalView,
              let snapshot = view.terminalContentSnapshot(region: .viewport) else { return [] }
        var lines: [String] = []
        for row in snapshot.rows.reversed() where lines.count < count {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(text) }
        }
        return lines.reversed()
    }

    // MARK: - Lifecycle

    /// Starts the shell if needed, then types the command.
    func start() {
        let wc = ensureWindow()
        switch state {
        case .running:
            return
        case .idle:
            typeCommand()
        case .stopped, .exited:
            var args = ["-l"]
            if config.interactive { args.append("-i") }
            var directory = Shell.expandTilde(config.directory)
            if config.createDirectory, let dir = directory {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            // A missing cwd makes posix_spawn fail silently inside the PTY; fall back to home and say so.
            var missingDirectory: String?
            if let dir = directory, !FileManager.default.fileExists(atPath: dir) {
                missingDirectory = dir
                directory = nil
            }
            wc.terminalView.startProcess(
                executable: Shell.path,
                args: args,
                environment: Shell.environment + ["MENUTERM_SESSION=\(config.name)"],
                execName: nil,
                currentDirectory: directory
            )
            setState(.idle)
            startPolling()
            if let missingDirectory {
                wc.feedNotice("작업 디렉터리 \(missingDirectory) 이(가) 없어 홈에서 시작합니다. 세션 편집에서 '없는 폴더면 생성'을 켜세요.")
            }
            // Typed-ahead input is held by the PTY until the shell reads it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.typeCommand()
            }
        }
    }

    /// Interrupts the running command (Ctrl-C), escalating to SIGTERM after 3 s.
    func stop() {
        guard state == .running, let wc = windowController else { return }
        wc.terminalView.send(data: [0x03][...])
        let pid = wc.terminalView.process?.shellPid ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.state == .running, pid > 0 else { return }
            Shell.signalChildren(of: pid, SIGTERM)
        }
    }

    func restart() {
        switch state {
        case .running:
            pendingRestart = true
            stop()
        case .idle, .stopped, .exited:
            start()
        }
    }

    /// Asks the shell to exit; used on quit so zshexit hooks run.
    func shutDown() {
        guard shellAlive, let wc = windowController else { return }
        if state == .running { wc.terminalView.send(data: [0x03][...]) }
        wc.terminalView.send(txt: "\u{15}exit\r") // ^U clears any typed text first
    }

    func showWindow() {
        let wc = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    /// Kills the shell outright and drops the window.
    func tearDown() {
        stopPolling()
        if shellAlive { windowController?.terminalView.terminate() }
        windowController?.close()
        windowController = nil
        state = .stopped
        stats = nil
    }

    // MARK: - Internals

    private func typeCommand() {
        guard shellAlive, let wc = windowController else { return }
        wc.terminalView.send(txt: "\u{15}\(config.command)\r")
        // Assume running until the poller sees otherwise; avoids a flicker to "idle".
        setState(.running)
    }

    private func ensureWindow() -> TerminalWindowController {
        if let wc = windowController { return wc }
        let wc = TerminalWindowController(session: self)
        wc.onProcessExit = { [weak self] code in
            guard let self else { return }
            self.stopPolling()
            self.stats = nil
            self.setState(.exited(code))
            if self.pendingRestart {
                self.pendingRestart = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.start() }
            }
        }
        windowController = wc
        return wc
    }

    private func startPolling() {
        pollTimer?.invalidate()
        lastCPU = [:]
        lastSampleAt = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        // .common keeps the timer firing while the status menu is open (menu tracking run-loop mode).
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Running = the shell has at least one child process. Also samples CPU/memory of the tree.
    private func poll() {
        guard shellAlive, let pid = windowController?.terminalView.process?.shellPid, pid > 0 else { return }
        let tree = Shell.processTree(of: pid)
        let busy = tree.count > 1
        if busy, state != .running {
            setState(.running)
        } else if !busy, state == .running {
            setState(.idle)
            windowController?.feedNotice("명령 종료 — 프롬프트로 돌아왔습니다. 재시작 버튼으로 다시 실행")
            if pendingRestart {
                pendingRestart = false
                typeCommand()
            }
        }
        sample(tree)
    }

    /// CPU% = growth of cumulative CPU time across pids seen in both samples, over wall-clock time.
    private func sample(_ tree: [pid_t]) {
        let now = Date().timeIntervalSince1970
        var cpu: [pid_t: UInt64] = [:]
        var memory: UInt64 = 0
        for p in tree {
            guard let u = Shell.usage(of: p) else { continue }
            cpu[p] = u.cpuNanoseconds
            memory += u.footprintBytes
        }
        var percent = 0.0
        if lastSampleAt > 0 {
            let wall = now - lastSampleAt
            var delta: UInt64 = 0
            for (p, t) in cpu { if let prev = lastCPU[p], t >= prev { delta += t - prev } }
            if wall > 0 { percent = Double(delta) / (wall * 1e9) * 100 }
        }
        lastCPU = cpu
        lastSampleAt = now
        stats = ResourceStats(cpuPercent: percent, memoryBytes: memory)
        if Session.debugStats {
            NSLog("MenuTerm: %@ pids=%d %@", config.name, tree.count, stats?.label ?? "")
        }
        onStatsChange?(self)
    }

    private func setState(_ new: SessionState) {
        guard state != new else { return }
        state = new
        windowController?.refreshStatus()
        onStateChange?(self)
    }
}
