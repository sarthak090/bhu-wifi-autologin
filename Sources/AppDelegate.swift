import AppKit
import CoreLocation
import Network
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CLLocationManagerDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let locationManager = CLLocationManager()
    let notifier = Notifier()
    let pathMonitor = NWPathMonitor()

    let stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    let accountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let lastCheckItem = NSMenuItem(title: "Last check: —", action: nil, keyEquivalent: "")
    let lastLoginItem = NSMenuItem(title: "Last login: —", action: nil, keyEquivalent: "")
    lazy var permissionItem = item("Allow Location to Detect Wi-Fi Name…", #selector(openLocationSettings))
    lazy var autoItem = item("Log In Automatically", #selector(toggleAuto))
    lazy var launchItem = item("Open at Login", #selector(toggleLaunchAtLogin))

    var timer: Timer?
    var pendingCheck: DispatchWorkItem?
    var settingsWindow: NSWindow?
    var checking = false
    var lastCheck: Date?
    var lastFailed = false
    var state: NetState?
    /// Set when the portal rejects the password, so we don't hammer it (and risk a lockout).
    var credentialsRejected = false

    let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var hasCredentials: Bool { Keychain.hasPassword(for: Prefs.username) }

    func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        buildMenu()

        notifier.onClick = { [weak self] alert in self?.handleNotificationClick(alert) }
        notifier.setup()

        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        // Every network change (joining Wi-Fi, coming back into range).
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.scheduleCheck(after: CONFIG.networkChangeDelay, reason: "network change") }
        }
        pathMonitor.start(queue: DispatchQueue(label: "bhu-wifi.path"))

        // Waking from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleCheck(after: CONFIG.networkChangeDelay, reason: "wake") }
        }

        // Periodic check for the 24 h session expiry.
        timer = Timer.scheduledTimer(withTimeInterval: CONFIG.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runCheck(reason: "timer") }
        }

        log("BHU WiFi \(CONFIG.version) started")
        if !hasCredentials { openSettings() }
        scheduleCheck(after: 0, reason: "launch")
    }

    /// Accessory apps have no menu bar, so Cmd-C/V/X/A need an (invisible) Edit menu to work in text fields.
    func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem())
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func buildMenu() {
        let menu = NSMenu()
        for info in [stateItem, accountItem, lastCheckItem, lastLoginItem] {
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(item("Refresh Status", #selector(refreshNow), "r"))
        menu.addItem(item("Log In Now", #selector(checkNow)))
        menu.addItem(item("Log Out", #selector(logOutNow)))
        menu.addItem(.separator())
        menu.addItem(autoItem)
        menu.addItem(launchItem)
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(item("Open Log", #selector(openLog), "l"))
        menu.addItem(item("Report an Issue…", #selector(reportIssue)))
        menu.addItem(item("About BHU WiFi", #selector(showAbout)))
        menu.addItem(withTitle: "Quit BHU WiFi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
        refreshUI()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.scheduleCheck(after: 0, reason: "location permission changed") }
    }

    // MARK: Checking and logging in

    func scheduleCheck(after delay: TimeInterval, reason: String) {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.runCheck(reason: reason) }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// True only when connected to the campus Wi-Fi; otherwise records why and stays idle.
    func onCampusWiFi(manual: Bool) -> Bool {
        if currentSSID() == Prefs.ssid { return true }
        let idle: NetState = locationAllowed(locationManager.authorizationStatus) ? .notOnBHU : .wifiNameUnknown
        if state != idle || manual {
            log(idle == .notOnBHU
                ? "not on \(Prefs.ssid); idle"
                : "cannot read Wi-Fi name: allow Location for BHU WiFi in System Settings; idle")
        }
        state = idle
        lastFailed = false
        refreshUI()
        return false
    }

    /// `refreshOnly` just re-reads the status (e.g. after logging in from a browser) and never logs in.
    func runCheck(reason: String, manual: Bool = false, refreshOnly: Bool = false) {
        guard !checking, onCampusWiFi(manual: manual) else { return }
        checking = true
        refreshUI()
        Task {
            defer { checking = false; refreshUI() }
            let detected = await probe()
            if detected != state { log("on \(Prefs.ssid): \(detected.rawValue)") }
            state = detected
            lastCheck = Date()
            lastCheckItem.title = "Last check: \(timeFormatter.string(from: Date()))"

            switch detected {
            case .online:
                lastFailed = false
                notifier.resolved()
                if manual { log("online — already logged in") }
            case .noNetwork:
                if manual { log("no network") }
            case .notOnBHU, .wifiNameUnknown:
                break
            case .other:
                log("skip: captive portal is not the BHU portal, not sending credentials")
            case .campusPortal where refreshOnly:
                if manual { log("refresh: not logged in") }
            case .campusPortal:
                await handlePortal(reason: reason, manual: manual)
            }
        }
    }

    func handlePortal(reason: String, manual: Bool) async {
        guard hasCredentials else {
            log("campus portal detected but no account is set up")
            notifier.post(.setup, title: "Not logged in to BHU Wi-Fi",
                          body: "Click to add your BHU Wi-Fi username and password.")
            return
        }
        if manual {
            credentialsRejected = false
        } else if credentialsRejected || !Prefs.autoLogin {
            log("campus portal detected; \(credentialsRejected ? "waiting for a password update" : "auto login is off")")
            notifier.post(.notLoggedIn, title: "Not logged in to BHU Wi-Fi", body: "Click to log in now.")
            return
        }
        await doLogin(reason: reason)
    }

    func doLogin(reason: String) async {
        let username = Prefs.username
        log("campus portal detected (\(reason)); logging in as \(username)")
        do {
            guard let password = try await Task.detached(operation: { try Keychain.password(for: username) }).value else {
                notifier.post(.setup, title: "Not logged in to BHU Wi-Fi", body: "Click to add your BHU Wi-Fi password.")
                return
            }
            let result = try await login(username: username, password: password)
            await sleep(2)
            let after = await probe()
            state = after

            switch result {
            case .accepted where after == .online:
                lastFailed = false
                credentialsRejected = false
                lastLoginItem.title = "Last login: \(timeFormatter.string(from: Date()))"
                log("login OK — now online")
                notifier.resolved()
                notifier.post(.loggedIn, title: "Logged in to BHU Wi-Fi", body: "Signed in as \(username).")
            case .accepted:
                lastFailed = true
                log("login FAILED — portal accepted the credentials but state is still \(after.rawValue)")
                notifier.post(.failed, title: "BHU Wi-Fi login didn't go through",
                              body: "Will retry automatically. Click to try again now.")
            case .rejected(let message):
                lastFailed = true
                credentialsRejected = true
                log("login REJECTED — \(message). Auto login paused until the password is updated or you click Log In Now")
                notifier.post(.rejected, title: "BHU Wi-Fi rejected your login",
                              body: "Check your username and password. Click to open Settings.")
            }
        } catch {
            lastFailed = true
            log("login FAILED — \(error.localizedDescription)")
            notifier.post(.failed, title: "BHU Wi-Fi login failed",
                          body: "Will retry automatically. Click to try again now.")
        }
    }

    func handleNotificationClick(_ alert: Alert) {
        switch alert {
        case .setup, .rejected: openSettings()
        case .notLoggedIn, .failed: checkNow()
        case .loggedIn: break
        }
    }

    // MARK: UI

    func refreshUI() {
        // Graduation cap plus a coloured status dot; dimmed when idle off campus.
        let (text, dot, dimmed): (String, NSColor?, Bool) = {
            if checking { return ("Checking…", .systemGray, false) }
            switch state {
            case .online?: return lastFailed ? ("Online (last login failed)", .systemOrange, false) : ("Logged in", .systemGreen, false)
            case .campusPortal?:
                if !hasCredentials { return ("Not logged in — add your account in Settings", .systemRed, false) }
                if credentialsRejected { return ("Login rejected — check your password", .systemRed, false) }
                return (lastFailed ? "Login failed — see log" : "Not logged in", .systemRed, false)
            case .other?: return ("Unknown portal on \(Prefs.ssid) (skipped)", .systemOrange, false)
            case .noNetwork?: return ("No network", .systemGray, false)
            case .notOnBHU?: return ("Not on \(Prefs.ssid) — idle", nil, true)
            case .wifiNameUnknown?: return ("Allow Location to detect \(Prefs.ssid)", .systemOrange, true)
            case nil: return ("Starting…", nil, false)
            }
        }()
        stateItem.title = "Status: \(text)"
        accountItem.title = Prefs.username.isEmpty ? "Account: not set up" : "Account: \(Prefs.username)"
        permissionItem.isHidden = locationAllowed(locationManager.authorizationStatus)
        autoItem.state = Prefs.autoLogin ? .on : .off
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: "BHU WiFi")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.appearsDisabled = dimmed
        button.attributedTitle = dot.map {
            NSAttributedString(string: "●", attributes: [.foregroundColor: $0, .font: NSFont.systemFont(ofSize: 8)])
        } ?? NSAttributedString(string: "")
        button.toolTip = "BHU WiFi — \(text)"
    }

    func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Actions

    @objc func refreshNow() { runCheck(reason: "refresh", manual: true, refreshOnly: true) }

    /// Opening the menu re-checks if the status is more than 15 s old,
    /// so a login or logout done in the browser shows up straight away.
    func menuWillOpen(_ menu: NSMenu) {
        if lastCheck.map({ Date().timeIntervalSince($0) > 15 }) ?? true {
            runCheck(reason: "menu opened", refreshOnly: true)
        }
    }

    @objc func checkNow() { runCheck(reason: "manual", manual: true) }

    @objc func logOutNow() {
        guard !checking, onCampusWiFi(manual: true) else { return }
        // Otherwise the next timer tick would log straight back in.
        Prefs.autoLogin = false
        checking = true
        refreshUI()
        Task {
            defer { checking = false; refreshUI() }
            log("logging out (auto login turned off)")
            do {
                try await logout()
            } catch {
                log("logout request failed — \(error.localizedDescription)")
            }
            await sleep(2)
            state = await probe()
            lastCheckItem.title = "Last check: \(timeFormatter.string(from: Date()))"
            log(state == .campusPortal ? "logged out" : "after logout, state: \(state?.rawValue ?? "unknown")")
        }
    }

    @objc func toggleAuto() {
        Prefs.autoLogin.toggle()
        log("auto login \(Prefs.autoLogin ? "enabled" : "disabled")")
        refreshUI()
        if Prefs.autoLogin { scheduleCheck(after: 0, reason: "auto login enabled") }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("open at login: \(error.localizedDescription)")
        }
    }

    @objc func toggleLaunchAtLogin() {
        setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
        refreshUI()
    }

    @objc func openSettings() {
        if let window = settingsWindow, window.isVisible { return bringToFront(window) }

        let initial = SettingsValues(
            username: Prefs.username,
            password: "",
            ssid: Prefs.ssid,
            autoLogin: Prefs.autoLogin,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            notifyNotLoggedIn: Prefs.notifyNotLoggedIn,
            notifyLoggedIn: Prefs.notifyLoggedIn
        )
        let view = SettingsView(
            initial: initial,
            hasSavedPassword: hasCredentials,
            onSave: { [weak self] values in self?.saveSettings(values) },
            onCancel: { [weak self] in self?.settingsWindow?.close() },
            onTestNotification: { [weak self] in self?.notifier.sendTest() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "BHU WiFi Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        bringToFront(window)
    }

    func saveSettings(_ values: SettingsValues) -> String? {
        let oldUsername = Prefs.username
        do {
            if !values.password.isEmpty { try Keychain.save(values.password, for: values.username) }
        } catch {
            return "Couldn't save the password to Keychain: \(error.localizedDescription)"
        }
        if !oldUsername.isEmpty && oldUsername != values.username { Keychain.delete(account: oldUsername) }

        Prefs.username = values.username
        Prefs.ssid = values.ssid
        Prefs.autoLogin = values.autoLogin
        Prefs.notifyNotLoggedIn = values.notifyNotLoggedIn
        Prefs.notifyLoggedIn = values.notifyLoggedIn
        setLaunchAtLogin(values.launchAtLogin)
        credentialsRejected = false
        lastFailed = false
        log("settings saved (account \(values.username)\(values.password.isEmpty ? "" : ", password updated"))")

        settingsWindow?.close()
        refreshUI()
        scheduleCheck(after: 0, reason: "settings saved")
        return nil
    }

    @objc func openLocationSettings() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        }
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: CONFIG.logURL.path) { log("log created") }
        NSWorkspace.shared.open(CONFIG.logURL)
    }

    @objc func reportIssue() {
        NSWorkspace.shared.open(CONFIG.repoURL.appendingPathComponent("issues"))
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: "Automatic login for the BHU campus Wi-Fi.\nUnofficial — not affiliated with Banaras Hindu University.\n\n")
        credits.append(NSAttributedString(string: CONFIG.repoURL.absoluteString, attributes: [.link: CONFIG.repoURL]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
