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
    /// Optional client-certificate (.p12) file path for mutual TLS (mTLS). Optional so
    /// older servers.json files decode fine.
    public var clientCertPath: String?
    /// Passphrase for the client-certificate .p12.
    public var clientCertPassword: String?
    /// Client-only path mappings. Optional so pre-mapping servers.json files still decode.
    public var pathMappings: [PathMapping]?

    public init(
        id: UUID = UUID(),
        name: String = "Localhost",
        host: String = "127.0.0.1",
        port: Int = 9091,
        path: String = "/transmission/rpc",
        useHTTPS: Bool = false,
        username: String = "",
        password: String = "",
        refreshInterval: Double = 3,
        clientCertPath: String? = nil,
        clientCertPassword: String? = nil,
        pathMappings: [PathMapping]? = nil
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
        self.clientCertPath = clientCertPath
        self.clientCertPassword = clientCertPassword
        self.pathMappings = pathMappings
    }

    /// The full RPC endpoint URL.
    ///
    /// Robust against convenience input in the host field: if the user entered
    /// the host with a scheme (`https://…`), a port (`host:9091`) or a trailing path,
    /// those are stripped. An explicit scheme or port in the host overrides `useHTTPS`
    /// and `port`. A bare IPv6 address (`::1`) is bracketed, and a path without a
    /// leading slash gets one.
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

        var effectivePort = port
        if rawHost.hasPrefix("["), let close = rawHost.firstIndex(of: "]") {
            // "[::1]" or "[::1]:9091"
            let rest = rawHost[rawHost.index(after: close)...]
            if rest.hasPrefix(":"), let p = Int(rest.dropFirst()) { effectivePort = p }
            rawHost = String(rawHost[...close])
        } else if rawHost.filter({ $0 == ":" }).count == 1, let colon = rawHost.firstIndex(of: ":") {
            // "example.com:9091"
            if let p = Int(rawHost[rawHost.index(after: colon)...]) { effectivePort = p }
            rawHost = String(rawHost[..<colon])
        } else if rawHost.contains(":") {
            // Bare IPv6 address: URLComponents only accepts it in brackets.
            rawHost = "[\(rawHost)]"
        }

        var rpcPath = path.trimmingCharacters(in: .whitespaces)
        if !rpcPath.isEmpty, !rpcPath.hasPrefix("/") { rpcPath = "/" + rpcPath }

        var components = URLComponents()
        components.scheme = scheme
        components.host = rawHost
        components.port = effectivePort
        components.path = rpcPath
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
