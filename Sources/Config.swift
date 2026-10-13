import Foundation

enum CONFIG {
    static let repoURL = URL(string: "https://github.com/sarthak090/bhu-wifi-autologin")!
    static let defaultSSID = "BHU-WiFi"
    static let keychainService = "BHU WiFi Login"

    // Connectivity probe (the same check macOS itself uses).
    static let probeHost = "captive.apple.com"
    static let probePath = "/hotspot-detect.html"
    static let probeTimeout: TimeInterval = 5
    static let probeAttempts = 3
    static let probeRetryDelay: TimeInterval = 3

    // Credentials are only ever sent when the portal redirect points at one of these.
    static let portalMarkers = ["arubanetworks", "10.40.51.37", "10.40.60.19"]

    // Aruba controller. The hostname only resolves on campus DNS, so connect by IP.
    static let loginIP = "10.40.60.19"
    static let loginHost = "securelogin.arubanetworks.com"
    static let loginPath = "/cgi-bin/login"
    static let logoutPath = "/cgi-bin/login?cmd=logout"
    static let loginRedirectURL = "https://www.bhu.ac.in/"
    static let loginSuccessMarker = "Authentication successful"
    static let loginTimeout: TimeInterval = 10

    static let checkInterval: TimeInterval = 120     // catches the 24 h session expiry
    static let networkChangeDelay: TimeInterval = 4  // let DHCP settle after a network change

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/bhu-wifi-login.log")

    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

/// User settings, stored in UserDefaults. The password lives in the Keychain, never here.
enum Prefs {
    private static let defaults = UserDefaults.standard

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    static var username: String {
        get { defaults.string(forKey: "username") ?? "" }
        set { defaults.set(newValue, forKey: "username") }
    }

    static var ssid: String {
        get { defaults.string(forKey: "ssid").flatMap { $0.isEmpty ? nil : $0 } ?? CONFIG.defaultSSID }
        set { defaults.set(newValue, forKey: "ssid") }
    }

    static var autoLogin: Bool {
        get { bool("autoLogin", default: true) }
        set { defaults.set(newValue, forKey: "autoLogin") }
    }

    static var notifyNotLoggedIn: Bool {
        get { bool("notifyNotLoggedIn", default: true) }
        set { defaults.set(newValue, forKey: "notifyNotLoggedIn") }
    }

    static var notifyLoggedIn: Bool {
        get { bool("notifyLoggedIn", default: false) }
        set { defaults.set(newValue, forKey: "notifyLoggedIn") }
    }
}
