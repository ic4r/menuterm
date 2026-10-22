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

/// One long-running session: an interactive login shell in a PTY into which the configured
/// command is typed. Running the command inside a real interactive shell keeps .zshrc
/// plugins well-behaved (a `zsh -lic cmd` run leaves their background workers orphaned).
final class Session {
    var config: SessionConfig
    private(set) var state: SessionState = .stopped
    private(set) var windowController: TerminalWindowController?
    var onStateChange: ((Session) -> Void)?

    private var pollTimer: Timer?
    private var pendingRestart = false

    init(config: SessionConfig) {
        self.config = config
    }

    var isRunning: Bool { state == .running }
    var shellAlive: Bool { state == .running || state == .idle }

    /// Last non-empty line visible in the terminal, for the menu subtitle.
    var lastLine: String? {
        guard let view = windowController?.terminalView,
              let snapshot = view.terminalContentSnapshot(region: .viewport) else { return nil }
        for row in snapshot.rows.reversed() {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
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
            wc.terminalView.startProcess(
                executable: Shell.path,
                args: args,
                environment: Shell.environment + ["MENUTERM_SESSION=\(config.name)"],
                execName: nil,
                currentDirectory: Shell.expandTilde(config.directory)
            )
            setState(.idle)
            startPolling()
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
        pollTimer?.invalidate()
        pollTimer = nil
        if shellAlive { windowController?.terminalView.terminate() }
        windowController?.close()
        windowController = nil
        state = .stopped
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
            self.pollTimer?.invalidate()
            self.pollTimer = nil
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Running = the shell has at least one child process.
    private func poll() {
        guard shellAlive, let pid = windowController?.terminalView.process?.shellPid, pid > 0 else { return }
        let busy = Shell.hasChildren(pid)
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
    }

    private func setState(_ new: SessionState) {
        guard state != new else { return }
        state = new
        windowController?.refreshStatus()
        onStateChange?(self)
    }
}
