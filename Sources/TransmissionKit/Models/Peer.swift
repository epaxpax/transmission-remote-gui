import Foundation

/// A connected peer (`peers` array).
public struct Peer: Codable, Hashable, Sendable, Identifiable {
    public var id: String { address }
    public var address: String
    public var clientName: String?
    public var flagStr: String?
    public var progress: Double
    public var rateToClient: Int
    public var rateToPeer: Int
    public var isEncrypted: Bool?

    private enum CodingKeys: String, CodingKey {
        case address
        case clientName
        case flagStr
        case progress
        case rateToClient
        case rateToPeer
        case isEncrypted
    }
}
