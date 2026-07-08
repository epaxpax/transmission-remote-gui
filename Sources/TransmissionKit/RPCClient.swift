import Foundation

/// Low-level client for the Transmission RPC (classic protocol).
///
/// Handles the `409 → X-Transmission-Session-Id` handshake: if the daemon responds
/// with 409, we store the session id from the header and resend the request once.
public actor RPCClient {
    public let config: ServerConfig
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The current session id received from the daemon (from the 409 handshake).
    private var sessionID: String?

    private static let sessionHeader = "X-Transmission-Session-Id"

    public init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Generic RPC call. `Response` is the type of the response's `arguments` field.
    func send<Args: Encodable, Response: Decodable>(
        method: String,
        arguments: Args,
        tag: Int = 0,
        includeIDsKey: Bool = true
    ) async throws -> Response {
        let envelope = RPCRequest(method: method, arguments: arguments, tag: tag)
        let body = try encoder.encode(envelope)
        return try await perform(body: body, allowRetry: true)
    }

    private func perform<Response: Decodable>(
        body: Data,
        allowRetry: Bool
    ) async throws -> Response {
        guard let url = config.url else { throw RPCError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: Self.sessionHeader)
        }
        if let auth = config.basicAuthHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RPCError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RPCError.transport("Nem HTTP válasz érkezett.")
        }

        switch http.statusCode {
        case 200:
            return try decodeResponse(data)
        case 409:
            // Session id handshake: record the new id and retry once.
            guard allowRetry,
                  let newID = http.value(forHTTPHeaderField: Self.sessionHeader) else {
                throw RPCError.missingSessionID
            }
            sessionID = newID
            return try await perform(body: body, allowRetry: false)
        case 401, 403:
            throw RPCError.unauthorized
        default:
            throw RPCError.http(http.statusCode)
        }
    }

    private func decodeResponse<Response: Decodable>(_ data: Data) throws -> Response {
        let envelope: RPCResponse<Response>
        do {
            envelope = try decoder.decode(RPCResponse<Response>.self, from: data)
        } catch {
            throw RPCError.decoding(error.localizedDescription)
        }
        guard envelope.result == "success" else {
            throw RPCError.rpcFailure(envelope.result)
        }
        guard let arguments = envelope.arguments else {
            throw RPCError.decoding("Hiányzó 'arguments' a válaszban.")
        }
        return arguments
    }
}
