import Foundation
import TransmissionKit

// Model integration test: every RPC is intercepted in-process; no daemon is contacted.
final class ConfirmationRPC: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var adds: [[String: Any]] = []

    static var submissions: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return adds
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let envelope = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let method = envelope["method"] as? String ?? ""
        var arguments: [String: Any] = [:]
        switch method {
        case "session-get": arguments = ["download-dir": "/downloads"]
        case "torrent-get": arguments = ["torrents": []]
        case "torrent-add":
            Self.lock.lock()
            Self.adds.append(envelope["arguments"] as? [String: Any] ?? [:])
            Self.lock.unlock()
        default: break
        }
        let data = try! JSONSerialization.data(withJSONObject: ["result": "success", "arguments": arguments])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct ConfirmationTests {
    @MainActor
    static func main() async throws {
        guard ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]?.contains("confirmation-test-home") == true
        else {
            fatalError("Run with an isolated confirmation-test-home")
        }
        precondition(URLProtocol.registerClass(ConfirmationRPC.self))
        defer { URLProtocol.unregisterClass(ConfirmationRPC.self) }
        let model = AppModel()
        precondition(model.servers.isEmpty, "Test home must start empty")
        let server = ServerConfig(name: "Confirmation test", host: "confirmation.invalid", refreshInterval: 3600)
        model.servers = [server]
        model.connect(to: server)
        for _ in 0..<500 where !model.isConnected {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.isConnected, "Mock connection failed")

        let file = URL(fileURLWithPath: "/tmp/confirmation.torrent")
        let magnet = URL(string: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789")!
        model.openIncoming([file, magnet, file])
        precondition(model.addRequest?.incoming == .file(file))
        let requestID = model.addRequest?.id
        model.openIncoming([file])
        precondition(model.addRequest?.id == requestID, "Duplicate open replaced the active dialog")
        await model.refresh()
        precondition(ConfirmationRPC.submissions.isEmpty, "Open or refresh submitted without confirmation")
        model.addRequest = nil  // Cancel
        model.presentNextIncoming()
        precondition(model.addRequest?.incoming == .link(magnet.absoluteString))
        model.addRequest = nil  // Cancel the second item too
        model.presentNextIncoming()
        precondition(model.addRequest == nil)
        precondition(ConfirmationRPC.submissions.isEmpty, "Cancel submitted a torrent")
        print("PASS: opens wait for confirmation, deduplicate, preserve order, and cancel without RPC")

        model.showAddTorrent()
        model.enqueueIncoming([.file(file)])
        precondition(model.addRequest?.incoming == nil, "External open replaced a manual Add dialog")
        model.addRequest = nil
        model.presentNextIncoming()
        precondition(model.addRequest?.incoming == .file(file))
        print("PASS: external opens wait behind manual Add")

        let other = ServerConfig(name: "Other", host: "other.invalid", refreshInterval: 3600)
        model.connect(to: other)
        precondition(model.addRequest == nil, "Server switch retained an old confirmation")
        model.disconnect()
        model.presentNextIncoming()
        precondition(model.addRequest == nil)
        print("PASS: switching servers discards pending confirmations")

        model.connect(to: server)
        await model.refresh()
        let added = await model.add(filename: magnet.absoluteString, paused: true, downloadDir: "/movies")
        precondition(added)
        precondition(ConfirmationRPC.submissions.count == 1)
        precondition(ConfirmationRPC.submissions[0]["download-dir"] as? String == "/movies")
        precondition(ConfirmationRPC.submissions[0]["paused"] as? Bool == true)
        precondition(model.defaultDownloadDir == nil || model.defaultDownloadDir == "/downloads")
        let readResult = await model.addTorrentFile(URL(fileURLWithPath: "/no-such-confirmation-test-file.torrent"))
        precondition(!readResult && model.actionError != nil)
        precondition(ConfirmationRPC.submissions.count == 1)
        model.disconnect()
        print("PASS: confirmed destination is sent per torrent; unreadable files report an error")
    }
}
