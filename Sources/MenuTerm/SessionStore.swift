import Foundation

/// Persisted definition of one long-running session.
struct SessionConfig: Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var command: String
    var directory: String?
    var autostart: Bool = true
    /// Run through `zsh -lic` (loads .zshrc: pyenv/nvm PATH etc.). Off = `zsh -lc`.
    var interactive: Bool = true

    init(id: UUID = UUID(), name: String, command: String, directory: String? = nil,
         autostart: Bool = true, interactive: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.directory = directory
        self.autostart = autostart
        self.interactive = interactive
    }

    // Tolerant decoding: keys added in later versions fall back to their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        directory = try c.decodeIfPresent(String.self, forKey: .directory)
        autostart = try c.decodeIfPresent(Bool.self, forKey: .autostart) ?? true
        interactive = try c.decodeIfPresent(Bool.self, forKey: .interactive) ?? true
    }
}

/// Loads and saves session definitions at ~/.config/menuterm/sessions.json.
final class SessionStore {
    private(set) var configs: [SessionConfig] = []
    let fileURL: URL

    init() {
        // MENUTERM_CONFIG_DIR overrides the default ~/.config/menuterm (used by tests).
        let override = ProcessInfo.processInfo.environment["MENUTERM_CONFIG_DIR"]
        let base = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/menuterm", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("sessions.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        configs = (try? JSONDecoder().decode([SessionConfig].self, from: data)) ?? []
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(configs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ config: SessionConfig) {
        configs.append(config)
        save()
    }

    func update(_ config: SessionConfig) {
        guard let i = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[i] = config
        save()
    }

    func remove(id: UUID) {
        configs.removeAll { $0.id == id }
        save()
    }
}
