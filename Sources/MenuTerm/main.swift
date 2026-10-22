import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// LSUIElement in Info.plist hides the Dock icon; .accessory covers `swift run` without a bundle.
app.setActivationPolicy(.accessory)
app.run()
