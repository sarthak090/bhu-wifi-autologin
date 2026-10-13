import Foundation
import Network

// Minimal HTTP/1.1 client.
// URLSession ignores a custom Host header and enforces ATS on plain HTTP,
// so the portal requests are written by hand over a raw TCP connection.

struct HTTPResponse {
    let status: Int
    let headers: [String: String]  // lower-cased names
    let body: String
}

enum HTTPError: LocalizedError {
    case timeout, malformed, connection(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "request timed out"
        case .malformed: return "malformed HTTP response"
        case .connection(let reason): return "connection failed: \(reason)"
        }
    }
}

final class ResumeOnce<T> {
    private var done = false
    private let lock = NSLock()
    let continuation: CheckedContinuation<T, Error>
    init(_ c: CheckedContinuation<T, Error>) { continuation = c }
    func resume(_ result: Result<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}

func httpRequest(
    method: String = "GET",
    host: String,
    connectTo: String? = nil,
    path: String,
    headers: [String: String] = [:],
    body: String? = nil,
    timeout: TimeInterval
) async throws -> HTTPResponse {
    var head = "\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: BHUWiFi/\(CONFIG.version)\r\nAccept: */*\r\nConnection: close\r\n"
    for (k, v) in headers { head += "\(k): \(v)\r\n" }
    let bodyData = Data((body ?? "").utf8)
    if body != nil { head += "Content-Length: \(bodyData.count)\r\n" }
    let requestData = Data((head + "\r\n").utf8) + bodyData

    let conn = NWConnection(host: NWEndpoint.Host(connectTo ?? host), port: 80, using: .tcp)
    // All callbacks below run on this one serial queue.
    let queue = DispatchQueue(label: "bhu-wifi.http")

    return try await withCheckedThrowingContinuation { cont in
        let once = ResumeOnce(cont)
        var received = Data()

        func finish(_ result: Result<HTTPResponse, Error>) {
            once.resume(result)
            conn.cancel()
        }

        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data { received.append(data) }
                if isComplete || error != nil {
                    if let parsed = parseResponse(received) { finish(.success(parsed)) }
                    else { finish(.failure(error ?? HTTPError.malformed)) }
                } else {
                    receive()
                }
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                conn.send(content: requestData, completion: .contentProcessed { error in
                    if let error { finish(.failure(error)) } else { receive() }
                })
            case .waiting(let error), .failed(let error):
                finish(.failure(HTTPError.connection(error.localizedDescription)))
            default:
                break
            }
        }
        queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(HTTPError.timeout)) }
        conn.start(queue: queue)
    }
}

func parseResponse(_ data: Data) -> HTTPResponse? {
    let text = String(decoding: data, as: UTF8.self)
    guard let split = text.range(of: "\r\n\r\n") else { return nil }
    let lines = text[..<split.lowerBound].components(separatedBy: "\r\n")
    guard let statusLine = lines.first else { return nil }
    let parts = statusLine.split(separator: " ")
    guard parts.count >= 2, let status = Int(parts[1]) else { return nil }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else { continue }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    return HTTPResponse(status: status, headers: headers, body: String(text[split.upperBound...]))
}

/// Visible text of an HTML page, whitespace-collapsed and truncated, for log messages.
func pageText(_ html: String, limit: Int = 300) -> String {
    let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    let words = noTags.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    return String(words.joined(separator: " ").prefix(limit))
}
