import Foundation

enum URLCodingError: LocalizedError, Equatable {
    case invalidPercentEncoding

    var errorDescription: String? {
        "URL-encoded input contains an invalid percent escape or invalid UTF-8."
    }
}

enum URLCoding {
    private static let percent: UInt8 = 0x25
    private static let hexDigits = Array("0123456789ABCDEF".utf8)

    static func encode(_ value: String) -> String {
        var encoded: [UInt8] = []
        encoded.reserveCapacity(value.utf8.count)

        for byte in value.utf8 {
            if isUnreserved(byte) {
                encoded.append(byte)
            } else {
                encoded.append(percent)
                encoded.append(hexDigits[Int(byte >> 4)])
                encoded.append(hexDigits[Int(byte & 0x0F)])
            }
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    static func decode(_ value: String) throws -> String {
        let input = Array(value.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(input.count)
        var index = 0

        while index < input.count {
            guard input[index] == percent else {
                decoded.append(input[index])
                index += 1
                continue
            }

            guard index + 2 < input.count,
                  let high = hexValue(input[index + 1]),
                  let low = hexValue(input[index + 2]) else {
                throw URLCodingError.invalidPercentEncoding
            }

            decoded.append((high << 4) | low)
            index += 3
        }

        guard let result = String(bytes: decoded, encoding: .utf8) else {
            throw URLCodingError.invalidPercentEncoding
        }
        return result
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x2D
            || byte == 0x2E
            || byte == 0x5F
            || byte == 0x7E
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            return byte - 0x30
        case 0x41...0x46:
            return byte - 0x41 + 10
        case 0x61...0x66:
            return byte - 0x61 + 10
        default:
            return nil
        }
    }
}
