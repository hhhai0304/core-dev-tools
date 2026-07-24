import Foundation

struct JSONArrayAlignmentPair: Equatable {
    let leftIndex: Int?
    let rightIndex: Int?
}

enum JSONArrayAligner {
    private static let preferredIdentityKeys = [
        "id",
        "uuid",
        "guid",
        "key",
        "code",
        "codes",
        "slug",
        "name",
    ]

    static func align(
        left: [JSONValue],
        right: [JSONValue]
    ) -> [JSONArrayAlignmentPair] {
        if let identityKey = identityKey(left: left, right: right) {
            return alignObjects(left: left, right: right, identityKey: identityKey)
        }
        return alignByValue(left: left, right: right)
    }

    private static func identityKey(
        left: [JSONValue],
        right: [JSONValue]
    ) -> String? {
        guard !left.isEmpty, !right.isEmpty else {
            return nil
        }

        for key in preferredIdentityKeys {
            guard let leftTokens = identityTokens(in: left, key: key),
                  let rightTokens = identityTokens(in: right, key: key),
                  !Set(leftTokens).isDisjoint(with: Set(rightTokens)) else {
                continue
            }
            return key
        }
        return nil
    }

    private static func identityTokens(
        in values: [JSONValue],
        key: String
    ) -> [String]? {
        var tokens: [String] = []
        var seen = Set<String>()

        for value in values {
            guard case let .object(entries) = value,
                  let identityValue = entries.first(where: { $0.key == key })?.value,
                  isSupportedIdentity(identityValue) else {
                return nil
            }

            let token = JSONRenderer.minified(identityValue)
            guard seen.insert(token).inserted else {
                return nil
            }
            tokens.append(token)
        }
        return tokens
    }

    private static func isSupportedIdentity(_ value: JSONValue) -> Bool {
        switch value {
        case .string, .number, .bool:
            return true
        case let .array(values):
            return values.allSatisfy { child in
                switch child {
                case .string, .number, .bool:
                    return true
                default:
                    return false
                }
            }
        default:
            return false
        }
    }

    private static func alignObjects(
        left: [JSONValue],
        right: [JSONValue],
        identityKey: String
    ) -> [JSONArrayAlignmentPair] {
        let leftTokens = identityTokens(in: left, key: identityKey)!
        let rightTokens = identityTokens(in: right, key: identityKey)!
        let rightIndexByToken = Dictionary(uniqueKeysWithValues: rightTokens.enumerated().map { ($0.element, $0.offset) })
        let leftTokenSet = Set(leftTokens)

        var pairs = leftTokens.enumerated().map { leftIndex, token in
            JSONArrayAlignmentPair(
                leftIndex: leftIndex,
                rightIndex: rightIndexByToken[token]
            )
        }

        pairs.append(contentsOf: rightTokens.enumerated().compactMap { rightIndex, token in
            guard !leftTokenSet.contains(token) else {
                return nil
            }
            return JSONArrayAlignmentPair(leftIndex: nil, rightIndex: rightIndex)
        })
        return pairs
    }

    private static func alignByValue(
        left: [JSONValue],
        right: [JSONValue]
    ) -> [JSONArrayAlignmentPair] {
        let lookaheadLimit = 24
        var pairs: [JSONArrayAlignmentPair] = []
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < left.count && rightIndex < right.count {
            if left[leftIndex] == right[rightIndex] {
                pairs.append(JSONArrayAlignmentPair(leftIndex: leftIndex, rightIndex: rightIndex))
                leftIndex += 1
                rightIndex += 1
                continue
            }

            let nextLeftMatch = firstMatch(
                for: right[rightIndex],
                in: left,
                range: (leftIndex + 1)..<min(left.count, leftIndex + 1 + lookaheadLimit)
            )
            let nextRightMatch = firstMatch(
                for: left[leftIndex],
                in: right,
                range: (rightIndex + 1)..<min(right.count, rightIndex + 1 + lookaheadLimit)
            )

            if let nextLeftMatch,
               nextRightMatch == nil || nextLeftMatch - leftIndex <= nextRightMatch! - rightIndex {
                pairs.append(JSONArrayAlignmentPair(leftIndex: leftIndex, rightIndex: nil))
                leftIndex += 1
            } else if nextRightMatch != nil {
                pairs.append(JSONArrayAlignmentPair(leftIndex: nil, rightIndex: rightIndex))
                rightIndex += 1
            } else {
                pairs.append(JSONArrayAlignmentPair(leftIndex: leftIndex, rightIndex: rightIndex))
                leftIndex += 1
                rightIndex += 1
            }
        }

        while leftIndex < left.count {
            pairs.append(JSONArrayAlignmentPair(leftIndex: leftIndex, rightIndex: nil))
            leftIndex += 1
        }
        while rightIndex < right.count {
            pairs.append(JSONArrayAlignmentPair(leftIndex: nil, rightIndex: rightIndex))
            rightIndex += 1
        }
        return pairs
    }

    private static func firstMatch(
        for value: JSONValue,
        in values: [JSONValue],
        range: Range<Int>
    ) -> Int? {
        range.first { values[$0] == value }
    }
}
