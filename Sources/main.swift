// BHU WiFi — menu bar app that keeps you logged in to the BHU campus Wi-Fi
// (Aruba ClearPass captive portal). Build with ./build.sh.

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
