import Foundation

indirect enum JSONValue: Equatable {
    case object([JSONObjectEntry])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    case missing
}

struct JSONObjectEntry: Equatable {
    let key: String
    let value: JSONValue
}

struct JSONParseError: LocalizedError, Equatable {
    let message: String
    let line: Int
    let column: Int

    var errorDescription: String? {
        "\(message) at line \(line), column \(column)."
    }
}

struct OrderedJSONParser {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    mutating func parse() throws -> JSONValue {
        skipWhitespace()
        guard !isAtEnd else {
            throw error("JSON input is empty")
        }

        let value = try parseValue()
        skipWhitespace()

        guard isAtEnd else {
            throw error("Unexpected content after the JSON value")
        }
        return value
    }

    private mutating func parseValue() throws -> JSONValue {
        guard let scalar = current else {
            throw error("Expected a JSON value")
        }

        switch scalar {
        case "{":
            return try parseObject()
        case "[":
            return try parseArray()
        case "\"":
            return .string(try parseString())
        case "t":
            try consumeKeyword("true")
            return .bool(true)
        case "f":
            try consumeKeyword("false")
            return .bool(false)
        case "n":
            try consumeKeyword("null")
            return .null
        case "-", "0"..."9":
            return .number(try parseNumber())
        default:
            throw error("Unexpected character '\(scalar)'")
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        advance()
        skipWhitespace()

        if consume("}") {
            return .object([])
        }

        var entries: [JSONObjectEntry] = []
        var keys = Set<String>()

        while true {
            guard current == "\"" else {
                throw error("Expected an object key")
            }

            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw error("Duplicate object key '\(key)'")
            }

            skipWhitespace()
            guard consume(":") else {
                throw error("Expected ':' after object key")
            }

            skipWhitespace()
            let value = try parseValue()
            entries.append(JSONObjectEntry(key: key, value: value))
            skipWhitespace()

            if consume("}") {
                return .object(entries)
            }

            guard consume(",") else {
                throw error("Expected ',' or '}' in object")
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        advance()
        skipWhitespace()

        if consume("]") {
            return .array([])
        }

        var values: [JSONValue] = []
        while true {
            values.append(try parseValue())
            skipWhitespace()

            if consume("]") {
                return .array(values)
            }

            guard consume(",") else {
                throw error("Expected ',' or ']' in array")
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        guard consume("\"") else {
            throw error("Expected a string")
        }

        var result = ""
        while let scalar = current {
            advance()

            if scalar == "\"" {
                return result
            }

            if scalar == "\\" {
                guard let escaped = current else {
                    throw error("Unterminated string escape")
                }
                advance()

                switch escaped {
                case "\"", "\\", "/":
                    result.unicodeScalars.append(escaped)
                case "b":
                    result.unicodeScalars.append("\u{0008}")
                case "f":
                    result.unicodeScalars.append("\u{000C}")
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                case "u":
                    let first = try parseHexQuad()
                    if (0xD800...0xDBFF).contains(first) {
                        guard consume("\\"), consume("u") else {
                            throw error("High surrogate must be followed by a low surrogate")
                        }
                        let second = try parseHexQuad()
                        guard (0xDC00...0xDFFF).contains(second) else {
                            throw error("Invalid low surrogate")
                        }
                        let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                        guard let unicodeScalar = UnicodeScalar(combined) else {
                            throw error("Invalid Unicode escape")
                        }
                        result.unicodeScalars.append(unicodeScalar)
                    } else {
                        guard !(0xDC00...0xDFFF).contains(first), let unicodeScalar = UnicodeScalar(first) else {
                            throw error("Invalid Unicode escape")
                        }
                        result.unicodeScalars.append(unicodeScalar)
                    }
                default:
                    throw error("Invalid string escape '\\\(escaped)'")
                }
            } else {
                guard scalar.value >= 0x20 else {
                    throw error("Unescaped control character in string")
                }
                result.unicodeScalars.append(scalar)
            }
        }

        throw error("Unterminated string")
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let scalar = current, let digit = hexValue(of: scalar) else {
                throw error("Expected four hexadecimal digits after '\\u'")
            }
            value = (value << 4) | digit
            advance()
        }
        return value
    }

    private func hexValue(of scalar: UnicodeScalar) -> UInt32? {
        switch scalar.value {
        case 48...57:
            return scalar.value - 48
        case 65...70:
            return scalar.value - 65 + 10
        case 97...102:
            return scalar.value - 97 + 10
        default:
            return nil
        }
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        _ = consume("-")

        if consume("0") {
            if let scalar = current, isDigit(scalar) {
                throw error("Leading zeros are not allowed in JSON numbers")
            }
        } else {
            guard let scalar = current, ("1"..."9").contains(scalar) else {
                throw error("Expected a digit")
            }
            advance()
            while let scalar = current, isDigit(scalar) {
                advance()
            }
        }

        if consume(".") {
            guard let scalar = current, isDigit(scalar) else {
                throw error("Expected a digit after decimal point")
            }
            while let scalar = current, isDigit(scalar) {
                advance()
            }
        }

        if consume("e") || consume("E") {
            _ = consume("+") || consume("-")
            guard let scalar = current, isDigit(scalar) else {
                throw error("Expected an exponent digit")
            }
            while let scalar = current, isDigit(scalar) {
                advance()
            }
        }

        return string(from: start..<index)
    }

    private func isDigit(_ scalar: UnicodeScalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private mutating func consumeKeyword(_ keyword: String) throws {
        for scalar in keyword.unicodeScalars {
            guard current == scalar else {
                throw error("Expected '\(keyword)'")
            }
            advance()
        }
    }

    private mutating func skipWhitespace() {
        while let scalar = current, scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" {
            advance()
        }
    }

    @discardableResult
    private mutating func consume(_ expected: UnicodeScalar) -> Bool {
        guard current == expected else {
            return false
        }
        advance()
        return true
    }

    private var current: UnicodeScalar? {
        isAtEnd ? nil : scalars[index]
    }

    private var isAtEnd: Bool {
        index >= scalars.count
    }

    private mutating func advance() {
        index += 1
    }

    private func string(from range: Range<Int>) -> String {
        var result = ""
        for scalar in scalars[range] {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private func error(_ message: String) -> JSONParseError {
        var line = 1
        var column = 1
        for scalar in scalars.prefix(index) {
            if scalar == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return JSONParseError(message: message, line: line, column: column)
    }
}

enum JSONRenderer {
    static func pretty(_ value: JSONValue, indentation: String) -> String {
        render(value, indentation: indentation, depth: 0)
    }

    static func minified(_ value: JSONValue) -> String {
        render(value, indentation: nil, depth: 0)
    }

    static func quotedString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\u{0008}":
                result += "\\b"
            case "\u{000C}":
                result += "\\f"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }

    private static func render(_ value: JSONValue, indentation: String?, depth: Int) -> String {
        switch value {
        case let .object(entries):
            guard !entries.isEmpty else {
                return "{}"
            }

            if let indentation {
                let childPrefix = String(repeating: indentation, count: depth + 1)
                let closingPrefix = String(repeating: indentation, count: depth)
                let body = entries.map { entry in
                    "\(childPrefix)\(quotedString(entry.key)): \(render(entry.value, indentation: indentation, depth: depth + 1))"
                }.joined(separator: ",\n")
                return "{\n\(body)\n\(closingPrefix)}"
            }

            let body = entries.map { entry in
                "\(quotedString(entry.key)):\(render(entry.value, indentation: nil, depth: depth + 1))"
            }.joined(separator: ",")
            return "{\(body)}"

        case let .array(values):
            guard !values.isEmpty else {
                return "[]"
            }

            if let indentation {
                let childPrefix = String(repeating: indentation, count: depth + 1)
                let closingPrefix = String(repeating: indentation, count: depth)
                let body = values.map { childPrefix + render($0, indentation: indentation, depth: depth + 1) }
                    .joined(separator: ",\n")
                return "[\n\(body)\n\(closingPrefix)]"
            }

            return "[\(values.map { render($0, indentation: nil, depth: depth + 1) }.joined(separator: ","))]"

        case let .string(value):
            return quotedString(value)
        case let .number(value):
            return value
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .missing:
            return ""
        }
    }
}

enum JSONDiffStatus: String, Codable, CaseIterable {
    case unchanged
    case changed
    case added
    case removed

    var label: String {
        rawValue.capitalized
    }
}

struct JSONDiffRow: Codable, Identifiable, Equatable {
    var id: String { path }

    let path: String
    let leftValue: String
    let rightValue: String
    let status: JSONDiffStatus
}

enum JSONDiffer {
    static func compare(_ left: JSONValue, _ right: JSONValue) -> [JSONDiffRow] {
        var rows: [JSONDiffRow] = []
        appendRows(left: left, right: right, path: "$", to: &rows)
        return rows
    }

    private static func appendRows(
        left: JSONValue,
        right: JSONValue,
        path: String,
        to rows: inout [JSONDiffRow]
    ) {
        switch (left, right) {
        case let (.object(leftEntries), .object(rightEntries)):
            if leftEntries.isEmpty && rightEntries.isEmpty {
                rows.append(row(path: path, left: left, right: right, status: .unchanged))
                return
            }

            let rightByKey = Dictionary(uniqueKeysWithValues: rightEntries.map { ($0.key, $0.value) })
            let leftKeys = Set(leftEntries.map(\.key))

            for entry in leftEntries {
                let childPath = pathForKey(entry.key, parent: path)
                if let rightValue = rightByKey[entry.key] {
                    appendRows(left: entry.value, right: rightValue, path: childPath, to: &rows)
                } else {
                    rows.append(JSONDiffRow(
                        path: childPath,
                        leftValue: JSONRenderer.minified(entry.value),
                        rightValue: "—",
                        status: .removed
                    ))
                }
            }

            for entry in rightEntries where !leftKeys.contains(entry.key) {
                rows.append(JSONDiffRow(
                    path: pathForKey(entry.key, parent: path),
                    leftValue: "—",
                    rightValue: JSONRenderer.minified(entry.value),
                    status: .added
                ))
            }

        case let (.array(leftValues), .array(rightValues)):
            if leftValues.isEmpty && rightValues.isEmpty {
                rows.append(row(path: path, left: left, right: right, status: .unchanged))
                return
            }

            for (alignedIndex, pair) in JSONArrayAligner.align(
                left: leftValues,
                right: rightValues
            ).enumerated() {
                let childPath = "\(path)[\(alignedIndex)]"
                switch (pair.leftIndex, pair.rightIndex) {
                case let (leftIndex?, rightIndex?):
                    appendRows(
                        left: leftValues[leftIndex],
                        right: rightValues[rightIndex],
                        path: childPath,
                        to: &rows
                    )

                case let (leftIndex?, nil):
                    rows.append(JSONDiffRow(
                        path: childPath,
                        leftValue: JSONRenderer.minified(leftValues[leftIndex]),
                        rightValue: "—",
                        status: .removed
                    ))

                case let (nil, rightIndex?):
                    rows.append(JSONDiffRow(
                        path: childPath,
                        leftValue: "—",
                        rightValue: JSONRenderer.minified(rightValues[rightIndex]),
                        status: .added
                    ))

                case (nil, nil):
                    break
                }
            }

        default:
            rows.append(row(
                path: path,
                left: left,
                right: right,
                status: left == right ? .unchanged : .changed
            ))
        }
    }

    private static func row(
        path: String,
        left: JSONValue,
        right: JSONValue,
        status: JSONDiffStatus
    ) -> JSONDiffRow {
        JSONDiffRow(
            path: path,
            leftValue: JSONRenderer.minified(left),
            rightValue: JSONRenderer.minified(right),
            status: status
        )
    }

    private static func pathForKey(_ key: String, parent: String) -> String {
        let isSimple = key.unicodeScalars.enumerated().allSatisfy { offset, scalar in
            let isLetter = ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
            let isDigit = ("0"..."9").contains(scalar)
            return offset == 0 ? isLetter : (isLetter || isDigit)
        } && !key.isEmpty

        if isSimple {
            return "\(parent).\(key)"
        }
        return "\(parent)[\(JSONRenderer.quotedString(key))]"
    }
}

func parseJSON(_ source: String) throws -> JSONValue {
    var parser = OrderedJSONParser(source)
    return try parser.parse()
}
