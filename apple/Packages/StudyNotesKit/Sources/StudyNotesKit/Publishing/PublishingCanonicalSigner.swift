import CryptoKit
import Foundation

public enum PublishingCanonicalSigner {
    public static func bodyHash(_ body: Data) -> String {
        let digest = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(digest)"
    }

    public static func canonicalString(
        method: String,
        url: URL,
        timestamp: String,
        nonce: String,
        bodyHash: String
    ) -> String {
        [
            method.uppercased(),
            canonicalPathAndQuery(url),
            timestamp,
            nonce,
            bodyHash
        ].joined(separator: "\n")
    }

    public static func headers(
        method: String,
        url: URL,
        body: Data,
        credential: PublishingCredential,
        timestamp: String,
        nonce: String
    ) throws -> [String: String] {
        let hash = bodyHash(body)
        let canonical = canonicalString(
            method: method,
            url: url,
            timestamp: timestamp,
            nonce: nonce,
            bodyHash: hash
        )
        let signature = try credential.signingPrivateKey()
            .signature(for: Data(canonical.utf8))
        return [
            "x-studynotes-key-id": credential.kid,
            "x-studynotes-timestamp": timestamp,
            "x-studynotes-nonce": nonce,
            "x-studynotes-signature": PublishingBase64URL.encode(signature),
            "x-studynotes-content-sha256": hash
        ]
    }

    static func canonicalPathAndQuery(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.path
        }
        let items = (components.percentEncodedQueryItems ?? [])
            .map {
                (
                    $0.name.removingPercentEncoding ?? $0.name,
                    ($0.value ?? "").removingPercentEncoding ?? ($0.value ?? "")
                )
            }
            .sorted {
                if $0.0 == $1.0 {
                    return $0.1.utf8.lexicographicallyPrecedes($1.1.utf8)
                }
                return $0.0.utf8.lexicographicallyPrecedes($1.0.utf8)
            }
        components.percentEncodedQuery = nil
        guard !items.isEmpty else {
            return components.percentEncodedPath.isEmpty
                ? "/"
                : components.percentEncodedPath
        }
        let query = items.map {
            "\(encodeURIComponent($0.0))=\(encodeURIComponent($0.1))"
        }.joined(separator: "&")
        return "\(components.percentEncodedPath)?\(query)"
    }

    static func encodeURIComponent(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum PublishingIdentifiers {
    public static func requestID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "_")
    }

    public static func nonce() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<24).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return PublishingBase64URL.encode(Data(bytes))
    }
}
