import Foundation
import Security

/// URLSession delegate answering mutual-TLS (mTLS) client-certificate challenges with an
/// identity loaded from a `.p12` file. Other challenges fall through to default handling
/// (so normal server-trust / HTTPS still works).
public final class ClientCertDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let identity: SecIdentity?

    public init(p12Path: String, password: String) {
        self.identity = Self.loadIdentity(path: p12Path, password: password)
    }

    public func urlSession(_ session: URLSession,
                           didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
              let identity else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(identity: identity, certificates: nil, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }

    private static func loadIdentity(path: String, password: String) -> SecIdentity? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let array = items as? [[String: Any]],
              let idObj = array.first?[kSecImportItemIdentity as String] else { return nil }
        return (idObj as! SecIdentity)
    }
}

public extension ServerConfig {
    /// A URLSession for this server: with an mTLS client-cert delegate when a `.p12` is
    /// configured, otherwise the shared session.
    func makeSession() -> URLSession {
        guard let path = clientCertPath, !path.isEmpty else { return .shared }
        let delegate = ClientCertDelegate(p12Path: path, password: clientCertPassword ?? "")
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
}
