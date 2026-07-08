import Foundation

/// Data needed to reach a Transmission daemon.
public struct ServerConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    /// RPC path, defaults to `/transmission/rpc`.
    public var path: String
    public var useHTTPS: Bool
    public var username: String
    /// In production the password is stored in the Keychain; kept here only for passing it along.
    public var password: String
    /// Refresh interval in seconds.
    public var refreshInterval: Double

    public init(
        id: UUID = UUID(),
        name: String = "Localhost",
        host: String = "127.0.0.1",
        port: Int = 9091,
        path: String = "/transmission/rpc",
        useHTTPS: Bool = false,
        username: String = "",
        password: String = "",
        refreshInterval: Double = 3
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.path = path
        self.useHTTPS = useHTTPS
        self.username = username
        self.password = password
        self.refreshInterval = refreshInterval
    }

    /// The full RPC endpoint URL.
    ///
    /// Robust against convenience input in the host field: if the user entered
    /// the host with a scheme (`https://…`) or a trailing path, those are
    /// stripped. An explicit scheme in the host overrides the `useHTTPS` flag.
    public var url: URL? {
        var rawHost = host.trimmingCharacters(in: .whitespaces)
        var scheme = useHTTPS ? "https" : "http"

        if let schemeSep = rawHost.range(of: "://") {
            let prefix = rawHost[..<schemeSep.lowerBound].lowercased()
            if prefix == "http" || prefix == "https" {
                scheme = prefix
            }
            rawHost = String(rawHost[schemeSep.upperBound...])
        }
        // Strip any path that ended up in the host field (e.g. "example.com/transmission").
        if let slash = rawHost.firstIndex(of: "/") {
            rawHost = String(rawHost[..<slash])
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = rawHost
        components.port = port
        components.path = path
        return components.url
    }

    /// Base64 `Authorization: Basic …` value, if a username is set.
    public var basicAuthHeader: String? {
        guard !username.isEmpty else { return nil }
        let raw = "\(username):\(password)"
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }
}
