import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let store = SessionStore()
    private var sessions: [Session] = []
    private var quickPanel: QuickTerminalPanel?
    private var quickHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("MenuTerm: config %@ (%d sessions)", store.fileURL.path, store.configs.count)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "MenuTerm")
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        statusItem.menu = menu
        installMainMenu()
        // ⌘⇧T toggles the Quick Command panel from anywhere.
        quickHotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.toggleQuick()
        }

        sessions = store.configs.map(makeSession)
        for s in sessions where s.config.autostart { s.start() }
        updateStatusTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        quickPanel?.close()
        sessions.forEach { $0.shutDown() }
        // Give shells up to 2.5 s to exit cleanly before the PTYs are torn down with the app.
        let deadline = Date().addingTimeInterval(2.5)
        while sessions.contains(where: \.shellAlive), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        sessions.forEach { $0.tearDown() }
    }

    /// An accessory app has no main menu by default, so ⌘X/⌘C/⌘V/⌘A never reach the
    /// first responder. A minimal Edit menu restores the standard editing key equivalents.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "MenuTerm 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: - Session helpers

    private func makeSession(_ config: SessionConfig) -> Session {
        let s = Session(config: config)
        s.onStateChange = { [weak self] _ in self?.updateStatusTitle() }
        return s
    }

    private func updateStatusTitle() {
        let running = sessions.filter(\.isRunning).count
        statusItem.button?.title = running > 0 ? " \(running)" : ""
    }

    private func session(for item: NSMenuItem) -> Session? {
        guard let id = item.representedObject as? UUID else { return nil }
        return sessions.first { $0.config.id == id }
    }

    // MARK: - NSMenuDelegate: rebuild the menu each time it opens

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let top = NSMenuItem()
        top.view = SplitMenuRow(
            left: ("⚡ Quick Command", { [weak self] in self?.openQuick() }),
            right: ("＋ 새 세션", { [weak self] in self?.addSession() })
        )
        menu.addItem(top)
        menu.addItem(.separator())

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "등록된 세션이 없습니다", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for s in sessions {
            let item = NSMenuItem(title: "\(s.state.symbol) \(s.config.name)", action: #selector(openSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.config.id
            item.toolTip = s.config.command
            let line = s.lastLine ?? "\(s.state.label) · \(s.config.command)"
            item.subtitle = String(line.prefix(70))
            item.submenu = buildSessionMenu(s)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "MenuTerm 종료", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    /// Per-session submenu: open plus lifecycle actions.
    private func buildSessionMenu(_ s: Session) -> NSMenu {
        let actions = NSMenu()
        actions.autoenablesItems = false
        let entries: [(String, Selector, Bool)] = [
            ("창 열기", #selector(openSession(_:)), true),
            ("시작", #selector(startSession(_:)), !s.isRunning),
            ("재시작", #selector(restartSession(_:)), s.state != .stopped),
            ("중지", #selector(stopSession(_:)), s.isRunning),
            ("편집…", #selector(editSession(_:)), true),
            ("삭제", #selector(removeSession(_:)), true),
        ]
        for (i, (title, sel, enabled)) in entries.enumerated() {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            it.representedObject = s.config.id
            it.isEnabled = enabled
            actions.addItem(it)
            if i == 0 || i == 3 { actions.addItem(.separator()) }
        }
        return actions
    }

    // MARK: - Actions

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let s = session(for: sender) else { return }
        if !s.isRunning { s.start() }
        s.showWindow()
    }

    @objc private func startSession(_ sender: NSMenuItem) { session(for: sender)?.start() }
    @objc private func restartSession(_ sender: NSMenuItem) { session(for: sender)?.restart() }
    @objc private func stopSession(_ sender: NSMenuItem) { session(for: sender)?.stop() }

    @objc private func editSession(_ sender: NSMenuItem) {
        guard let s = session(for: sender), let updated = NewSessionDialog.run(editing: s.config) else { return }
        s.config = updated
        s.windowController?.window?.title = updated.name
        s.windowController?.refreshStatus()
        store.update(updated)
    }

    @objc private func removeSession(_ sender: NSMenuItem) {
        guard let s = session(for: sender) else { return }
        let alert = NSAlert()
        alert.messageText = "세션 '\(s.config.name)' 을(를) 삭제할까요?"
        alert.informativeText = s.isRunning ? "실행 중인 프로세스도 함께 종료됩니다." : ""
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        s.tearDown()
        sessions.removeAll { $0.config.id == s.config.id }
        store.remove(id: s.config.id)
        updateStatusTitle()
    }

    @objc private func addSession() {
        guard let config = NewSessionDialog.run() else { return }
        store.add(config)
        let s = makeSession(config)
        sessions.append(s)
        s.start()
        s.showWindow()
    }

    /// Hotkey behaviour: hide the panel when it is already in front, otherwise show it.
    private func toggleQuick() {
        if let panel = quickPanel, panel.isVisible, panel.isKeyWindow {
            panel.orderOut(nil)
        } else {
            openQuick()
        }
    }

    @objc private func openQuick() {
        if let panel = quickPanel {
            panel.present()
            return
        }
        let panel = QuickTerminalPanel()
        panel.onClosed = { [weak self] in self?.quickPanel = nil }
        quickPanel = panel
        panel.present()
        panel.launch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
