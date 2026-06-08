import AppKit

// fenêtre runs as an "accessory" app: no Dock icon, no app switcher entry,
// just a menu-bar item and the overlay panel. We set the activation policy in
// code so we don't need an Info.plist / .app bundle during development.
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
