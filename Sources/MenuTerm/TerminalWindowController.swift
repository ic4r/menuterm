import AppKit
import SwiftTerm

/// Window hosting one session's terminal with a small status bar on top.
final class TerminalWindowController: NSWindowController, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    private unowned let session: Session
    let terminalView: LocalProcessTerminalView
    private let statusLabel = NSTextField(labelWithString: "")
    private let restartButton = NSButton(title: "재시작", target: nil, action: nil)
    private let stopButton = NSButton(title: "중지", target: nil, action: nil)
    var onProcessExit: ((Int32?) -> Void)?

    init(session: Session) {
        self.session = session
        let frame = NSRect(x: 0, y: 0, width: 820, height: 480)
        terminalView = LocalProcessTerminalView(frame: frame)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = session.config.name
        window.setFrameAutosaveName("MenuTerm.session.\(session.config.id.uuidString)")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        refreshStatus()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildContent() {
        guard let window else { return }
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        restartButton.target = self
        restartButton.action = #selector(restartTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        restartButton.bezelStyle = .accessoryBarAction
        stopButton.bezelStyle = .accessoryBarAction
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let bar = NSStackView(views: [statusLabel, NSView(), restartButton, stopButton])
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        content.addSubview(terminalView)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 30),
            terminalView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.initialFirstResponder = terminalView
    }

    func refreshStatus() {
        let c = session.config
        statusLabel.stringValue = "\(session.state.symbol) \(session.state.label)  ·  \(c.command)" +
            (c.directory.map { "  ·  \($0)" } ?? "")
        stopButton.isEnabled = session.isRunning
    }

    /// Prints an app-side notice into the terminal, distinct from process output.
    func feedNotice(_ text: String) {
        terminalView.feed(text: "\u{1b}[2m[MenuTerm] \(text)\u{1b}[0m\r\n")
    }

    @objc private func restartTapped() { session.restart() }
    @objc private func stopTapped() { session.stop() }

    // MARK: NSWindowDelegate — closing hides the window; the process keeps running.

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.makeFirstResponder(terminalView)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        window?.title = title.isEmpty ? session.config.name : "\(session.config.name) — \(title)"
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        NSLog("MenuTerm: process failed to start for %@: %@", session.config.name, String(describing: error))
        DispatchQueue.main.async { [self] in
            feedNotice("실행 실패: \(error)")
            onProcessExit?(nil)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [self] in
            feedNotice("셸 종료 (code \(exitCode.map(String.init) ?? "signal")) — 재시작 버튼으로 다시 실행")
            onProcessExit?(exitCode)
        }
    }
}
