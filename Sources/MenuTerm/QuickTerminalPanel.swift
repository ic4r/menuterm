import AppKit
import SwiftTerm

/// Floating panel for one-off commands. Closing it ends the shell.
final class QuickTerminalPanel: NSPanel, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    private let terminalView: LocalProcessTerminalView
    var onClosed: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let size = NSSize(width: 720, height: 260)
        terminalView = LocalProcessTerminalView(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Quick Command"
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrameAutosaveName("MenuTerm.quick")
        delegate = self

        terminalView.autoresizingMask = [.width, .height]
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.processDelegate = self
        contentView = terminalView
        initialFirstResponder = terminalView

        if frameAutosaveName.isEmpty || !setFrameUsingName("MenuTerm.quick") {
            positionBelowMenuBar()
        }
    }

    private func positionBelowMenuBar() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - frame.width - 12, y: visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
    }

    func launch() {
        terminalView.startProcess(
            executable: Shell.path,
            args: ["-l", "-i"],
            environment: Shell.environment,
            execName: nil,
            currentDirectory: NSHomeDirectory()
        )
    }

    func present() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(terminalView)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        terminalView.terminate()
        onClosed?()
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title.isEmpty ? "Quick Command" : "Quick Command — \(title)"
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Shell exited (e.g. the user typed `exit`): close the panel.
        DispatchQueue.main.async { [self] in
            if isVisible { close() }
        }
    }
}
