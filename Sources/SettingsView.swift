import SwiftUI

struct SettingsValues {
    var username: String
    var password: String  // empty = keep the saved password
    var ssid: String
    var autoLogin: Bool
    var launchAtLogin: Bool
    var notifyNotLoggedIn: Bool
    var notifyLoggedIn: Bool
}

struct SettingsView: View {
    let savedUsername: String
    let hasSavedPassword: Bool
    /// Returns an error message to show, or nil when saved.
    let onSave: (SettingsValues) -> String?
    let onCancel: () -> Void
    let onTestNotification: () -> Void

    @State private var values: SettingsValues
    @State private var error: String?

    init(initial: SettingsValues, hasSavedPassword: Bool,
         onSave: @escaping (SettingsValues) -> String?, onCancel: @escaping () -> Void,
         onTestNotification: @escaping () -> Void) {
        savedUsername = initial.username
        self.hasSavedPassword = hasSavedPassword
        self.onSave = onSave
        self.onCancel = onCancel
        self.onTestNotification = onTestNotification
        _values = State(initialValue: initial)
    }

    private var trimmedUsername: String { values.username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var keepsSavedPassword: Bool { hasSavedPassword && trimmedUsername == savedUsername }
    private var canSave: Bool { !trimmedUsername.isEmpty && (keepsSavedPassword || !values.password.isEmpty) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Username", text: $values.username, prompt: Text("e.g. 151.123456"))
                    SecureField("Password", text: $values.password,
                                prompt: Text(keepsSavedPassword ? "Saved — leave blank to keep" : "Your BHU Wi-Fi password"))
                } header: {
                    Text("BHU Wi-Fi account")
                } footer: {
                    Text("The password is stored in your Mac's Keychain. It is only ever sent to the BHU login portal, and only while you are connected to \(values.ssid.isEmpty ? CONFIG.defaultSSID : values.ssid).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Behaviour") {
                    Toggle("Log in automatically", isOn: $values.autoLogin)
                    Toggle("Open at login", isOn: $values.launchAtLogin)
                    Toggle("Notify me when I'm not logged in", isOn: $values.notifyNotLoggedIn)
                    Toggle("Notify me after each automatic login", isOn: $values.notifyLoggedIn)
                    Button("Send Test Notification", action: onTestNotification)
                }

                Section {
                    TextField("Wi-Fi network name", text: $values.ssid, prompt: Text(CONFIG.defaultSSID))
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("The app stays idle on every other network.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            // A grouped Form scrolls, so it has no natural height; without this the window collapses.
            .frame(height: 560)

            if let error {
                Text(error).foregroundStyle(.red).font(.callout).padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") {
                    var v = values
                    v.username = trimmedUsername
                    v.ssid = v.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
                    error = onSave(v)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 440)
    }
}
