import Foundation

public enum RPCError: Error, LocalizedError, Sendable {
    case invalidURL
    case transport(String)
    case http(Int)
    case unauthorized
    /// The daemon's `result` field was not `"success"`.
    case rpcFailure(String)
    case decoding(String)
    /// No valid session id was received even after the 409 handshake.
    case missingSessionID

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Érvénytelen szerver URL."
        case .transport(let message):
            return "Hálózati hiba: \(message)"
        case .http(let code):
            return "HTTP hiba: \(code)"
        case .unauthorized:
            return "Hibás felhasználónév vagy jelszó."
        case .rpcFailure(let message):
            return "A daemon hibát adott: \(message)"
        case .decoding(let message):
            return "Feldolgozási hiba: \(message)"
        case .missingSessionID:
            return "Nem sikerült megszerezni a session azonosítót."
        }
    }
}
