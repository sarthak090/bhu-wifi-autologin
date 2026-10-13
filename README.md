# BHU WiFi 🎓

**Website:** https://sarthak090.github.io/bhu-wifi-autologin/

A tiny macOS menu bar app that keeps you logged in to the **BHU campus Wi-Fi** (`BHU-WiFi`, Aruba ClearPass captive portal).

No more typing your username and password every 24 hours, or every time you walk out of range and come back.

> Unofficial student project. Not affiliated with or endorsed by Banaras Hindu University or its Computer Centre. Use it only with your own BHU Wi-Fi account.

## Features

- **Logs you in automatically**: when you join BHU-WiFi, come back into range, wake your Mac, or when the 24-hour session expires (checked every 2 minutes).
- **Enter your account once.** The username and password are saved in your Mac's Keychain, and you can change them anytime in **Settings…**.
- **Tells you when you're not logged in**, for example when the portal rejects your password or auto login is off.
- **Protects your account:** if the portal rejects your password, auto login pauses instead of retrying and risking a lockout. It starts again when you update your password or click **Log In Now**.
- **Only active on BHU-WiFi.** On any other network (home, Starbucks, hotspot) it does nothing, and your password is only ever sent to the BHU login portal.
- **Refresh Status** (⌘R) re-checks without logging in, so a login or logout done in the browser shows up right away. Opening the menu also refreshes a stale status.
- **Log In Now** and **Log Out** buttons, **Open at Login**, and a log file for troubleshooting.
- Works on Apple Silicon and Intel Macs running macOS 13 Ventura or later.

### Menu bar icon

| Icon | Meaning |
|---|---|
| 🎓 green dot | Logged in |
| 🎓 red dot | Not logged in, or the login was rejected |
| 🎓 orange dot | Needs attention (Location permission, unknown portal, last login failed) |
| 🎓 grey dot | Checking, or no network |
| 🎓 faded, no dot | Not on BHU-WiFi, so the app is idle |

## Install

Open **Terminal** and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/sarthak090/bhu-wifi-autologin/main/install.sh | bash
```

<details>
<summary>Or install by hand</summary>

1. Download `BHU-WiFi.zip` from the [latest release](https://github.com/sarthak090/bhu-wifi-autologin/releases/latest) and unzip it.
2. Drag **BHU WiFi.app** into **Applications**.
3. Open it. macOS will say it "cannot verify the developer", because the app isn't notarized (that needs a paid Apple developer account). Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.

</details>

## First-time setup

1. A **Settings** window opens. Enter your BHU Wi-Fi **username** and **password**, then click **Save**.
2. When macOS asks, **allow Location**. macOS only tells apps the Wi-Fi network *name* if they have Location access. The app uses it only to check that you're on BHU-WiFi, and never reads or stores your location.
3. Turn on **Open at login** in Settings so it starts with your Mac.
4. **Recommended:** go to **System Settings → Wi-Fi → (i) next to BHU-WiFi** and set **Private Wi-Fi Address** to **Off**. Your Mac's address then stays the same between reconnects, so the portal remembers you.

To change your password later, click the 🎓 icon, then **Settings…**, type the new password, and click **Save**.

### After an update

Each new version is a new unsigned build, so macOS may ask again:
- **"BHU WiFi wants to use your confidential information stored in 'BHU WiFi Login'"**: click **Always Allow**. This is the app reading your saved password.
- **Location**: allow it again.

## How it works

1. Every 2 minutes, and on every network change or wake, the app checks whether the Wi-Fi name is `BHU-WiFi`. If it isn't, it stops there.
2. It requests `http://captive.apple.com/hotspot-detect.html`, the same check macOS uses.
   - `Success` means you're online, so it does nothing.
   - Aruba's redirect to the BHU portal (`10.40.51.37` / `securelogin.arubanetworks.com`) means you're not logged in.
3. It sends one login request, the same one the portal's own login form sends:
   `POST http://10.40.60.19/cgi-bin/login` with `Host: securelogin.arubanetworks.com` and the form fields `user`, `password`, `cmd=authenticate`.
4. It checks the connection again and updates the icon.

Everything is in `Sources/`. `Portal.swift` has the network logic, and `Config.swift` has every address and timing.

## Troubleshooting

- **Log:** 🎓 → **Open Log**, or run `tail -f ~/Library/Logs/bhu-wifi-login.log`.
- **Icon has an orange dot and says "Allow Location":** 🎓 → **Allow Location to Detect Wi-Fi Name…**, then turn on BHU WiFi.
- **"Login rejected":** check your username and password in Settings. Auto login stays paused until you save them again.
- **The icon is missing:** on MacBooks with a notch, menu bar icons can hide behind it. Quit a few other menu bar apps to make room.
- **Notifications:** if you don't see any, allow notifications for **BHU WiFi** in System Settings → Notifications. Use **Settings → Send Test Notification** to check. Release builds aren't Apple-signed, so clicking a notification doesn't open the app; use the 🎓 menu instead.

## Uninstall

1. Click 🎓, then **Quit BHU WiFi**.
2. In Terminal, run:

```sh
rm -rf "/Applications/BHU WiFi.app" ~/Applications/"BHU WiFi.app"
rm -f ~/Library/Logs/bhu-wifi-login.log
defaults delete io.github.sarthak090.bhu-wifi
security delete-generic-password -s "BHU WiFi Login"
```

If you turned on **Open at login**, remove BHU WiFi from **System Settings → General → Login Items** too.

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). No Xcode project and no dependencies.

```sh
git clone https://github.com/sarthak090/bhu-wifi-autologin.git
cd bhu-wifi-autologin
./build.sh          # build, install to /Applications and launch
./build.sh dist     # build dist/BHU-WiFi.zip
```

### Releasing

Bump `VERSION`, commit, then tag:

```sh
git tag v1.0.1 && git push origin v1.0.1
```

GitHub Actions builds the universal app and attaches `BHU-WiFi.zip` to the release. That's the file `install.sh` downloads.

## Contributing

Issues and pull requests are welcome, especially if the portal changes, or if you'd like to add support for another campus that uses an Aruba portal. Please **never include your password or a HAR file containing it** in an issue.

## License

[MIT](LICENSE)
