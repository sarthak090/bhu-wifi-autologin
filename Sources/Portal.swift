import CoreLocation
import CoreWLAN
import Foundation

enum NetState: String {
    case online = "online"
    case campusPortal = "campus-portal"
    case other = "other"
    case noNetwork = "no-network"
    case notOnBHU = "not-on-campus-wifi"
    case wifiNameUnknown = "wifi-name-unknown"
}

// macOS only reveals the SSID to apps with Location Services permission.
let currentSSID = { CWWiFiClient.shared().interface()?.ssid() }

let locationAllowed = { (status: CLAuthorizationStatus) in
    status != .notDetermined && status != .denied && status != .restricted
}

// Aruba first answers with a meta refresh back to the probe host
// (…?cmd=redirect&arubalp=…); only that second request is redirected to the portal.
func metaRefreshPath(_ body: String) -> String? {
    let prefix = "http://\(CONFIG.probeHost)/"
    guard let start = body.range(of: "url=\(prefix)") else { return nil }
    let rest = body[start.upperBound...]
    let end = rest.firstIndex(where: { "'\" >".contains($0) }) ?? rest.endIndex
    return "/" + rest[..<end]
}

func probe() async -> NetState {
    for attempt in 1...CONFIG.probeAttempts {
        do {
            var res = try await httpRequest(host: CONFIG.probeHost, path: CONFIG.probePath, timeout: CONFIG.probeTimeout)
            if res.status == 200 && res.body.contains("Success") { return .online }
            if res.headers["location"] == nil, let path = metaRefreshPath(res.body) {
                res = try await httpRequest(host: CONFIG.probeHost, path: path, timeout: CONFIG.probeTimeout)
                if res.status == 200 && res.body.contains("Success") { return .online }
            }
            let haystack = (res.headers["location"] ?? "") + "\n" + res.body
            if CONFIG.portalMarkers.contains(where: { haystack.contains($0) }) { return .campusPortal }
            log("unrecognised probe response: status=\(res.status) location=\(res.headers["location"] ?? "-") body=\(pageText(res.body))")
            return .other
        } catch {
            if attempt < CONFIG.probeAttempts { await sleep(CONFIG.probeRetryDelay) }
        }
    }
    return .noNetwork
}

enum LoginResult {
    case accepted
    case rejected(String)  // the portal's message, for the log
}

let formEncode = { (s: String) -> String in
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

func login(username: String, password: String) async throws -> LoginResult {
    let fields: [(String, String)] = [
        ("user", username),
        ("password", password),
        ("url", CONFIG.loginRedirectURL),
        ("cmd", "authenticate"),
        ("Login", "Log In"),
    ]
    let body = fields.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")
    let res = try await httpRequest(
        method: "POST",
        host: CONFIG.loginHost,
        connectTo: CONFIG.loginIP,
        path: CONFIG.loginPath,
        headers: ["Content-Type": "application/x-www-form-urlencoded"],
        body: body,
        timeout: CONFIG.loginTimeout
    )
    if res.body.contains(CONFIG.loginSuccessMarker) { return .accepted }
    let location = res.headers["location"].map { $0.removingPercentEncoding ?? $0 }
    return .rejected("status=\(res.status) \(location.map { "location=\($0) " } ?? "")\(pageText(res.body))")
}

func logout() async throws {
    _ = try await httpRequest(
        host: CONFIG.loginHost,
        connectTo: CONFIG.loginIP,
        path: CONFIG.logoutPath,
        timeout: CONFIG.loginTimeout
    )
}
