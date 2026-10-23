import AppKit

// `MenuTerm --write-iconset <dir>` renders the app icon PNGs and exits (used by Scripts/build-app.sh).
if let i = CommandLine.arguments.firstIndex(of: "--write-iconset"), i + 1 < CommandLine.arguments.count {
    do {
        try AppIcon.writeIconset(to: CommandLine.arguments[i + 1])
        exit(0)
    } catch {
        FileHandle.standardError.write("iconset failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// LSUIElement in Info.plist hides the Dock icon; .accessory covers `swift run` without a bundle.
app.setActivationPolicy(.accessory)
app.run()
