import AppKit

/// Modal form for creating or editing a session definition.
enum NewSessionDialog {
    static func run(editing existing: SessionConfig? = nil) -> SessionConfig? {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "새 세션" : "세션 편집"
        alert.informativeText = "명령은 로그인 셸(\(Shell.path))에서 실행되며, 창을 닫아도 계속 실행됩니다."
        alert.addButton(withTitle: existing == nil ? "추가" : "저장")
        alert.addButton(withTitle: "취소")

        let nameField = NSTextField(string: existing?.name ?? "")
        nameField.placeholderString = "이름 (예: api-server)"
        let dirField = NSTextField(string: existing?.directory ?? "")
        dirField.placeholderString = "작업 디렉터리 (선택, 예: ~/work/api)"
        let createDir = NSButton(checkboxWithTitle: "없는 폴더면 생성", target: nil, action: nil)
        createDir.state = (existing?.createDirectory ?? false) ? .on : .off
        let commandField = NSTextField(string: existing?.command ?? "")
        commandField.placeholderString = "명령 (예: npm run dev)"
        let autostart = NSButton(checkboxWithTitle: "앱 시작 시 자동 실행", target: nil, action: nil)
        autostart.state = (existing?.autostart ?? true) ? .on : .off
        let interactive = NSButton(checkboxWithTitle: "인터랙티브 셸로 실행 (-i, .zshrc 로드)", target: nil, action: nil)
        interactive.state = (existing?.interactive ?? true) ? .on : .off
        let favorite = NSButton(checkboxWithTitle: "자주 쓰는 세션으로 등록 (메뉴에서 매번 새 복사본을 염, 1개만 가능)", target: nil, action: nil)
        favorite.state = (existing?.favorite ?? false) ? .on : .off

        let form = NSStackView(views: [nameField, dirField, createDir, commandField, autostart, interactive, favorite])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.setCustomSpacing(4, after: dirField)
        form.translatesAutoresizingMaskIntoConstraints = false
        for f in [nameField, dirField, commandField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 210))
        holder.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: holder.topAnchor),
            form.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            form.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        alert.accessoryView = holder
        alert.window.initialFirstResponder = nameField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let command = commandField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        var name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = command }
        let dir = dirField.stringValue.trimmingCharacters(in: .whitespaces)

        var config = existing ?? SessionConfig(name: name, command: command)
        config.name = name
        config.command = command
        config.directory = dir.isEmpty ? nil : dir
        config.createDirectory = createDir.state == .on
        config.autostart = autostart.state == .on
        config.interactive = interactive.state == .on
        config.favorite = favorite.state == .on
        return config
    }
}
