import Foundation

enum JWTDecoderError: LocalizedError, Equatable {
    case malformedStructure
    case invalidSegmentEncoding(Int)
    case nonUTF8Segment(Int)

    var errorDescription: String? {
        switch self {
        case .malformedStructure:
            return "A JWT must contain three dot-separated segments: header, payload, and signature."
        case .invalidSegmentEncoding(let segment):
            return "JWT \(Self.segmentName(segment)) segment is not valid base64url."
        case .nonUTF8Segment(let segment):
            return "JWT \(Self.segmentName(segment)) segment did not decode to UTF-8."
        }
    }

    private static func segmentName(_ segment: Int) -> String {
        segment == 1 ? "header" : "payload"
    }
}

struct DecodedJWT {
    let header: JSONValue
    let payload: JSONValue
    let signature: String
}

struct JWTClaimTimestamp: Identifiable, Equatable {
    let name: String
    let date: Date

    var id: String { name }
    var isPast: Bool { date < Date() }
}

enum JWTDecoder {
    /// Numeric claims that read more naturally as dates than epoch seconds.
    private static let timestampClaims = ["exp", "iat", "nbf"]

    static func decode(_ token: String) throws -> DecodedJWT {
        let segments = segments(of: token)
        guard segments.count == 3, !segments[0].isEmpty, !segments[1].isEmpty else {
            throw JWTDecoderError.malformedStructure
        }

        return DecodedJWT(
            header: try decodeSegment(segments[0], segment: 1),
            payload: try decodeSegment(segments[1], segment: 2),
            signature: String(segments[2])
        )
    }

    /// Returns the raw signature segment, or nil when the token is not three
    /// dot-separated segments. The signature is binary data, so it is kept in
    /// its base64url form rather than decoded.
    static func signatureSegment(of token: String) -> String? {
        let segments = segments(of: token)
        return segments.count == 3 ? String(segments[2]) : nil
    }

    static func timestamps(in payload: JSONValue) -> [JWTClaimTimestamp] {
        guard case let .object(entries) = payload else {
            return []
        }
        return timestampClaims.compactMap { name in
            guard let entry = entries.first(where: { $0.key == name }),
                  case let .number(raw) = entry.value,
                  let seconds = TimeInterval(raw) else {
                return nil
            }
            return JWTClaimTimestamp(name: name, date: Date(timeIntervalSince1970: seconds))
        }
    }

    private static func segments(of token: String) -> [Substring] {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
    }

    private static func decodeSegment(_ segment: Substring, segment index: Int) throws -> JSONValue {
        guard let data = base64URLDecode(segment) else {
            throw JWTDecoderError.invalidSegmentEncoding(index)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw JWTDecoderError.nonUTF8Segment(index)
        }
        return try parseJSON(text)
    }

    static func base64URLDecode(_ segment: Substring) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
