import Foundation

/// The `ids` parameter of `torrent-get` / action requests.
///
/// - `all`: omit `ids` (applies to all torrents)
/// - `ids`: specific ids and/or hash strings
/// - `recentlyActive`: the daemon's delta-refresh mode
public enum RPCIds: Encodable, Sendable {
    case all
    case ids([RPCIdentifier])
    case recentlyActive

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all:
            // An empty array = no filtering; valid even in the classic protocol,
            // but the caller usually does not send this at all (see encodeIfPresent).
            try container.encode([Int]())
        case .recentlyActive:
            try container.encode("recently-active")
        case .ids(let list):
            try container.encode(list)
        }
    }
}

/// A value identifying a torrent: numeric id or hash string.
public enum RPCIdentifier: Encodable, Sendable {
    case id(Int)
    case hash(String)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .id(let value): try container.encode(value)
        case .hash(let value): try container.encode(value)
        }
    }
}

/// Generic RPC request envelope: `{ "method": …, "arguments": …, "tag": … }`.
struct RPCRequest<Args: Encodable>: Encodable {
    let method: String
    let arguments: Args
    let tag: Int
}

/// Generic RPC response envelope: `{ "result": …, "arguments": …, "tag": … }`.
struct RPCResponse<Args: Decodable>: Decodable {
    let result: String
    let arguments: Args?
    let tag: Int?
}

/// Empty arguments for methods that take no parameters,
/// and for empty response objects (`"arguments": {}`).
struct EmptyArgs: Codable {}
