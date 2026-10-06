import Foundation

enum SQLFormatError: LocalizedError, Equatable {
    case unterminatedString(line: Int, column: Int)
    case unterminatedIdentifier(line: Int, column: Int)
    case unterminatedComment(line: Int, column: Int)

    var errorDescription: String? {
        switch self {
        case let .unterminatedString(line, column):
            return "Unterminated string literal at line \(line), column \(column)."
        case let .unterminatedIdentifier(line, column):
            return "Unterminated quoted identifier at line \(line), column \(column)."
        case let .unterminatedComment(line, column):
            return "Unterminated block comment at line \(line), column \(column)."
        }
    }
}

enum SQLTokenKind: Equatable {
    case word
    case quotedIdentifier
    case string
    case number
    case parameter
    case lineComment
    case blockComment
    case openParen
    case closeParen
    case comma
    case semicolon
    case dot
    case doubleColon
    case op
}

struct SQLToken: Equatable {
    let kind: SQLTokenKind
    let text: String
    let utf16Location: Int
    let utf16Length: Int
    let precededByNewline: Bool
}

struct SQLTokenizer {
    private let scalars: [UnicodeScalar]
    private let strict: Bool
    private var index = 0
    private var utf16Offset = 0
    private var sawNewline = false

    init(_ source: String, strict: Bool) {
        scalars = Array(source.unicodeScalars)
        self.strict = strict
    }

    mutating func tokenize() throws -> [SQLToken] {
        var tokens: [SQLToken] = []
        skipWhitespace()
        while !isAtEnd {
            tokens.append(try scanToken())
            skipWhitespace()
        }
        return tokens
    }

    private mutating func scanToken() throws -> SQLToken {
        let startIndex = index
        let startUTF16 = utf16Offset
        let hadNewline = sawNewline
        sawNewline = false

        func token(_ kind: SQLTokenKind) -> SQLToken {
            SQLToken(
                kind: kind,
                text: substring(from: startIndex),
                utf16Location: startUTF16,
                utf16Length: utf16Offset - startUTF16,
                precededByNewline: hadNewline
            )
        }

        let scalar = current!

        if scalar == "-", peek(1) == "-" {
            advance()
            advance()
            while let next = current, next != "\n" {
                advance()
            }
            return token(.lineComment)
        }

        if scalar == "/", peek(1) == "*" {
            try scanBlockComment()
            return token(.blockComment)
        }

        if scalar == "#", peek(1) != ">" {
            advance()
            while let next = current, next != "\n" {
                advance()
            }
            return token(.lineComment)
        }

        if scalar == "'" {
            try scanQuoted("'", escapesByDoubling: true)
            return token(.string)
        }

        if scalar == "\"" || scalar == "`" {
            try scanQuoted(scalar, escapesByDoubling: true)
            return token(.quotedIdentifier)
        }

        if scalar == "[" {
            try scanBracketed()
            return token(.quotedIdentifier)
        }

        if scalar == "$" {
            if try scanDollarQuoted() {
                return token(.string)
            }
            if let next = peek(1), isDigit(next) {
                advance()
                while let next = current, isDigit(next) {
                    advance()
                }
                return token(.parameter)
            }
            advance()
            return token(.op)
        }

        if scalar == "?" {
            advance()
            if let next = current, next == "|" || next == "&" {
                advance()
                return token(.op)
            }
            return token(.parameter)
        }

        if scalar == ":" {
            advance()
            if let next = current {
                if next == ":" {
                    advance()
                    return token(.doubleColon)
                }
                if next == "=" {
                    advance()
                    return token(.op)
                }
                if isWordStart(next) {
                    while let next = current, isWordContinue(next) {
                        advance()
                    }
                    return token(.parameter)
                }
            }
            return token(.op)
        }

        if scalar == "@" {
            if peek(1) == ">" {
                advance()
                advance()
                return token(.op)
            }
            advance()
            if let next = current, next == "@" {
                advance()
            }
            var isParameter = false
            while let next = current, isWordContinue(next) {
                advance()
                isParameter = true
            }
            return token(isParameter ? .parameter : .op)
        }

        if isDigit(scalar) || (scalar == "." && peek(1).map(isDigit) == true) {
            scanNumber()
            return token(.number)
        }

        if isWordStart(scalar) {
            while let next = current, isWordContinue(next) {
                advance()
            }
            let word = substring(from: startIndex).uppercased()
            if ["N", "E", "B", "X", "R"].contains(word), current == "'" {
                try scanQuoted("'", escapesByDoubling: true)
                return token(.string)
            }
            if word == "U", current == "&", let next = peek(1), next == "'" || next == "\"" {
                let delimiter = next
                advance()
                try scanQuoted(delimiter, escapesByDoubling: true)
                return token(delimiter == "'" ? .string : .quotedIdentifier)
            }
            return token(.word)
        }

        switch scalar {
        case "(":
            advance()
            return token(.openParen)
        case ")":
            advance()
            return token(.closeParen)
        case ",":
            advance()
            return token(.comma)
        case ";":
            advance()
            return token(.semicolon)
        case ".":
            advance()
            return token(.dot)
        default:
            break
        }

        if let length = matchOperator() {
            for _ in 0..<length {
                advance()
            }
            return token(.op)
        }

        advance()
        return token(.op)
    }

    private mutating func scanQuoted(_ delimiter: UnicodeScalar, escapesByDoubling: Bool) throws {
        let startIndex = index
        advance()
        while let scalar = current {
            if scalar == "\\" {
                advance()
                if !isAtEnd {
                    advance()
                }
                continue
            }
            if scalar == delimiter {
                if escapesByDoubling, peek(1) == delimiter {
                    advance()
                    advance()
                    continue
                }
                advance()
                return
            }
            advance()
        }
        if strict {
            let (line, column) = position(of: startIndex)
            throw delimiter == "'"
                ? SQLFormatError.unterminatedString(line: line, column: column)
                : SQLFormatError.unterminatedIdentifier(line: line, column: column)
        }
    }

    private mutating func scanBracketed() throws {
        let startIndex = index
        advance()
        while let scalar = current {
            if scalar == "]" {
                if peek(1) == "]" {
                    advance()
                    advance()
                    continue
                }
                advance()
                return
            }
            advance()
        }
        if strict {
            let (line, column) = position(of: startIndex)
            throw SQLFormatError.unterminatedIdentifier(line: line, column: column)
        }
    }

    private mutating func scanBlockComment() throws {
        let startIndex = index
        var depth = 0
        while !isAtEnd {
            if current == "/", peek(1) == "*" {
                depth += 1
                advance()
                advance()
            } else if current == "*", peek(1) == "/" {
                depth -= 1
                advance()
                advance()
                if depth == 0 {
                    return
                }
            } else {
                advance()
            }
        }
        if strict {
            let (line, column) = position(of: startIndex)
            throw SQLFormatError.unterminatedComment(line: line, column: column)
        }
    }

    private mutating func scanDollarQuoted() throws -> Bool {
        var cursor = index + 1
        while cursor < scalars.count, isDollarTagScalar(scalars[cursor]) {
            cursor += 1
        }
        guard cursor < scalars.count, scalars[cursor] == "$" else {
            return false
        }
        let tag = substring(from: index, to: cursor + 1)
        index = cursor + 1
        utf16Offset += tag.utf16.count

        let tagScalars = Array(tag.unicodeScalars)
        while !isAtEnd {
            if current == "$", matchesSequence(tagScalars) {
                for _ in 0..<tagScalars.count {
                    advance()
                }
                return true
            }
            advance()
        }
        if strict {
            let (line, column) = position(of: index)
            throw SQLFormatError.unterminatedString(line: line, column: column)
        }
        return true
    }

    private mutating func scanNumber() {
        if current == "0", let next = peek(1), next == "x" || next == "X" {
            advance()
            advance()
            while let next = current, isHexDigit(next) || next == "_" {
                advance()
            }
            return
        }

        if current == "." {
            advance()
        }
        while let next = current, isDigit(next) || next == "_" {
            advance()
        }
        if current == ".", let next = peek(1), isDigit(next) {
            advance()
            while let next = current, isDigit(next) || next == "_" {
                advance()
            }
        }
        if let next = current, next == "e" || next == "E" {
            var lookahead = index + 1
            if lookahead < scalars.count, scalars[lookahead] == "+" || scalars[lookahead] == "-" {
                lookahead += 1
            }
            if lookahead < scalars.count, isDigit(scalars[lookahead]) {
                while index < lookahead {
                    advance()
                }
                while let next = current, isDigit(next) || next == "_" {
                    advance()
                }
            }
        }
    }

    private func matchOperator() -> Int? {
        for symbol in SQLFormatter.operators {
            let symbolScalars = Array(symbol.unicodeScalars)
            if matchesSequence(symbolScalars) {
                return symbolScalars.count
            }
        }
        return nil
    }

    private func matchesSequence(_ sequence: [UnicodeScalar]) -> Bool {
        guard index + sequence.count <= scalars.count else {
            return false
        }
        for offset in 0..<sequence.count where scalars[index + offset] != sequence[offset] {
            return false
        }
        return true
    }

    private mutating func skipWhitespace() {
        while let scalar = current, scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
            if scalar == "\n" {
                sawNewline = true
            }
            advance()
        }
    }

    private var current: UnicodeScalar? {
        isAtEnd ? nil : scalars[index]
    }

    private var isAtEnd: Bool {
        index >= scalars.count
    }

    private func peek(_ offset: Int) -> UnicodeScalar? {
        let target = index + offset
        return target < scalars.count ? scalars[target] : nil
    }

    private mutating func advance() {
        utf16Offset += scalars[index].utf16.count
        index += 1
    }

    private func substring(from start: Int, to end: Int? = nil) -> String {
        var result = ""
        for scalar in scalars[start ..< (end ?? index)] {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private func position(of scalarIndex: Int) -> (line: Int, column: Int) {
        var line = 1
        var column = 1
        for scalar in scalars.prefix(scalarIndex) {
            if scalar == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }

    private func isDigit(_ scalar: UnicodeScalar) -> Bool {
        ("0" ... "9").contains(scalar)
    }

    private func isHexDigit(_ scalar: UnicodeScalar) -> Bool {
        ("0" ... "9").contains(scalar) || ("a" ... "f").contains(scalar) || ("A" ... "F").contains(scalar)
    }

    private func isWordStart(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar) || scalar == "_"
    }

    private func isWordContinue(_ scalar: UnicodeScalar) -> Bool {
        isWordStart(scalar) || isDigit(scalar) || scalar == "$"
    }

    private func isDollarTagScalar(_ scalar: UnicodeScalar) -> Bool {
        isWordStart(scalar) || isDigit(scalar)
    }
}

enum SQLFormatter {
    static func beautify(_ source: String, indentation: String) throws -> String {
        var tokenizer = SQLTokenizer(source, strict: true)
        let tokens = try tokenizer.tokenize()
        var beautifier = SQLBeautifier(tokens: tokens, indentUnit: indentation)
        return beautifier.render()
    }

    static func minify(_ source: String) throws -> String {
        var tokenizer = SQLTokenizer(source, strict: true)
        let tokens = try tokenizer.tokenize()
        var result = ""
        var previous: SQLToken?
        var previousUnary = false
        for token in tokens where token.kind != .lineComment && token.kind != .blockComment {
            if let previous, spacingBetween(previous, token, previousIsUnaryMinus: previousUnary) {
                result += " "
            }
            result += token.text
            previousUnary = token.kind == .op && (token.text == "-" || token.text == "+") && impliesUnary(previous)
            previous = token
        }
        return result
    }

    static func isStylizedWord(_ word: String) -> Bool {
        stylizedWords.contains(word.uppercased())
    }

    static let stylizedWords: Set<String> = keywords.union(functionNames)

    static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "AS", "ON", "IN", "IS",
        "LIKE", "ILIKE", "RLIKE", "BETWEEN", "EXISTS", "CASE", "WHEN", "THEN", "ELSE",
        "END", "DISTINCT", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
        "NATURAL", "APPLY", "GROUP", "BY", "ORDER", "ASC", "DESC", "NULLS", "FIRST",
        "LAST", "LIMIT", "OFFSET", "FETCH", "NEXT", "ROW", "ROWS", "ONLY", "TIES",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "ALTER",
        "DROP", "TABLE", "TEMP", "TEMPORARY", "VIEW", "INDEX", "SCHEMA", "DATABASE",
        "UNION", "ALL", "EXCEPT", "INTERSECT", "HAVING", "WITH", "RECURSIVE", "OVER",
        "PARTITION", "RETURNING", "USING", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
        "DEFAULT", "CONSTRAINT", "UNIQUE", "CHECK", "COLLATE", "BEGIN", "COMMIT",
        "ROLLBACK", "TRANSACTION", "WORK", "GRANT", "REVOKE", "TRUNCATE", "TRUE",
        "FALSE", "ESCAPE", "FILTER", "LATERAL", "FOR", "SHARE", "WAIT", "NOWAIT",
        "SKIP", "LOCKED", "TOP", "PERCENT", "STRAIGHT_JOIN", "CASCADE", "RESTRICT",
        "IDENTITY", "AUTO_INCREMENT", "CHARACTER", "VARYING", "PRECISION", "ZONE",
        "TO", "DO", "BOOLEAN", "INTEGER", "INT", "BIGINT", "SMALLINT", "TINYINT",
        "REAL", "DOUBLE", "DATE", "DATETIME", "TEXT", "BLOB", "SERIAL",
        "UUID", "JSON", "JSONB", "ENUM", "ADD", "COLUMN", "RENAME", "MODIFY", "AFTER",
        "BEFORE", "DECLARE", "EXEC", "EXECUTE", "MERGE", "MATCHED", "EXPLAIN",
        "ANALYZE", "VERBOSE", "SHOW", "DESCRIBE", "IF", "INTERVAL", "UNSIGNED",
        "ZEROFILL", "SEPARATOR", "DUAL",
    ]

    static let functionNames: Set<String> = [
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "IFNULL", "ISNULL",
        "NVL", "NVL2", "IIF", "NOW", "CURDATE", "CURTIME", "SYSDATE", "GETDATE",
        "CURRENT_TIMESTAMP", "CURRENT_DATE", "CURRENT_TIME", "UPPER", "LOWER",
        "INITCAP", "TRIM", "LTRIM", "RTRIM", "SUBSTRING", "SUBSTR", "MID", "LEFT",
        "RIGHT", "LENGTH", "LEN", "CHAR_LENGTH", "CHARACTER_LENGTH", "REPLACE",
        "CONCAT", "CONCAT_WS", "REVERSE", "REPEAT", "LPAD", "RPAD", "INSTR",
        "POSITION", "LOCATE", "SPLIT_PART", "REGEXP_REPLACE", "ABS", "ROUND", "FLOOR",
        "CEIL", "CEILING", "MOD", "POWER", "POW", "SQRT", "EXP", "LN", "LOG", "LOG10",
        "SIGN", "PI", "RANDOM", "RAND", "TRUNC", "GREATEST", "LEAST", "ROW_NUMBER",
        "RANK", "DENSE_RANK", "NTILE", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        "NTH_VALUE", "PERCENT_RANK", "CUME_DIST", "CAST", "CONVERT", "TRY_CAST",
        "TRY_CONVERT", "EXTRACT", "DATE_TRUNC", "DATEADD", "DATEDIFF", "DATEPART",
        "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND", "ARRAY_AGG", "STRING_AGG",
        "GROUP_CONCAT", "LISTAGG", "JSON_EXTRACT", "JSON_VALUE", "JSON_QUERY",
        "JSON_ARRAYAGG", "JSON_OBJECTAGG", "STUFF", "FORMAT", "ANY_VALUE",
        "CHAR", "VARCHAR", "NCHAR", "NVARCHAR", "CHARACTER", "DECIMAL", "NUMERIC",
        "FLOAT", "TIME", "TIMESTAMP", "BIT", "VARBIT", "BINARY", "VARBINARY", "ROW",
    ]

    static let clausePhrases: [(words: [String], breakable: Bool)] = [
        (["NATURAL", "LEFT", "OUTER", "JOIN"], false),
        (["NATURAL", "RIGHT", "OUTER", "JOIN"], false),
        (["NATURAL", "FULL", "OUTER", "JOIN"], false),
        (["LEFT", "OUTER", "JOIN"], false),
        (["RIGHT", "OUTER", "JOIN"], false),
        (["FULL", "OUTER", "JOIN"], false),
        (["NATURAL", "LEFT", "JOIN"], false),
        (["NATURAL", "RIGHT", "JOIN"], false),
        (["NATURAL", "FULL", "JOIN"], false),
        (["NATURAL", "INNER", "JOIN"], false),
        (["NATURAL", "CROSS", "JOIN"], false),
        (["GROUP", "BY"], false),
        (["ORDER", "BY"], false),
        (["INSERT", "INTO"], false),
        (["DELETE", "FROM"], false),
        (["UNION", "ALL"], false),
        (["UNION", "DISTINCT"], false),
        (["EXCEPT", "ALL"], false),
        (["INTERSECT", "ALL"], false),
        (["LEFT", "JOIN"], false),
        (["RIGHT", "JOIN"], false),
        (["FULL", "JOIN"], false),
        (["INNER", "JOIN"], false),
        (["CROSS", "JOIN"], false),
        (["NATURAL", "JOIN"], false),
        (["CROSS", "APPLY"], false),
        (["OUTER", "APPLY"], false),
        (["JOIN"], false),
        (["SELECT"], false),
        (["FROM"], false),
        (["WHERE"], true),
        (["HAVING"], true),
        (["LIMIT"], false),
        (["OFFSET"], false),
        (["UNION"], false),
        (["EXCEPT"], false),
        (["INTERSECT"], false),
        (["VALUES"], false),
        (["SET"], false),
        (["UPDATE"], false),
        (["DELETE"], false),
        (["INSERT"], false),
        (["WITH"], false),
        (["CREATE"], false),
        (["ALTER"], false),
        (["DROP"], false),
        (["TRUNCATE"], false),
        (["RETURNING"], false),
        (["BEGIN"], false),
        (["COMMIT"], false),
        (["ROLLBACK"], false),
        (["GRANT"], false),
        (["REVOKE"], false),
        (["FETCH"], false),
        (["DECLARE"], false),
        (["EXEC"], false),
        (["EXECUTE"], false),
        (["MERGE"], false),
        (["STRAIGHT_JOIN"], false),
    ]

    static let operators: [String] = [
        "!~~*", "!~~", "!~*", "!~", "~~*", "~~", "~*", "->>", "->", "#>>", "#>",
        "<=>", "<=", ">=", "<>", "!=", "!<", "!>", "||", ":=", "=>", "<<", ">>",
        "&<", "&>", "<@", "@>", "|/", "=", "<", ">", "+", "-", "*", "/", "%", "&", "|", "^",
        "~", "!",
    ]

    fileprivate static func spacingBetween(
        _ previous: SQLToken,
        _ token: SQLToken,
        previousIsUnaryMinus: Bool
    ) -> Bool {
        if previousIsUnaryMinus {
            return false
        }
        switch token.kind {
        case .comma, .semicolon, .closeParen, .dot, .doubleColon:
            return false
        case .openParen:
            switch previous.kind {
            case .comma, .closeParen, .semicolon, .op:
                return true
            case .word:
                let upper = previous.text.uppercased()
                return keywords.contains(upper) && !functionNames.contains(upper)
            default:
                return false
            }
        default:
            switch previous.kind {
            case .openParen, .dot, .doubleColon:
                return false
            default:
                return true
            }
        }
    }

    fileprivate static func impliesUnary(_ token: SQLToken?) -> Bool {
        guard let token else {
            return true
        }
        switch token.kind {
        case .op, .openParen, .comma, .semicolon, .dot, .doubleColon:
            return true
        case .word:
            let upper = token.text.uppercased()
            return keywords.contains(upper) && !functionNames.contains(upper)
        default:
            return false
        }
    }
}

private struct SQLBeautifier {
    private enum Context {
        case paren(expanded: Bool)
        case caseBlock
    }

    private let tokens: [SQLToken]
    private let indentUnit: String

    private var lines: [String] = []
    private var current = ""
    private var currentIndent = 0
    private var pendingIndent = 0
    private var hasContent = false
    private var contexts: [Context] = []
    private var clauseStack: [(breakable: Bool, pendingBetween: Bool)] = []
    private var clauseIsBreakable = false
    private var pendingBetween = false
    private var statementBoundary = false
    private var lastToken: SQLToken?
    private var lastTokenUnary = false
    private var index = 0

    private var depth: Int {
        contexts.count
    }

    init(tokens: [SQLToken], indentUnit: String) {
        self.tokens = tokens
        self.indentUnit = indentUnit
    }

    mutating func render() -> String {
        while index < tokens.count {
            let token = tokens[index]
            switch token.kind {
            case .lineComment:
                emitLineComment(token)
            case .blockComment:
                emitBlockComment(token)
            case .openParen:
                emitOpenParen(token)
            case .closeParen:
                emitCloseParen(token)
            case .word:
                emitWord(token)
            case .semicolon:
                emit(token, text: ";")
                finishLine()
                statementBoundary = true
            default:
                let unary = token.kind == .op && (token.text == "-" || token.text == "+") && previousImpliesUnary()
                emit(token, text: token.text)
                if unary {
                    lastTokenUnary = true
                }
            }
            index += 1
        }
        finishLine()
        return lines.joined(separator: "\n")
    }

    private func previousImpliesUnary() -> Bool {
        SQLFormatter.impliesUnary(lastToken)
    }

    private mutating func emit(_ token: SQLToken, text: String) {
        if statementBoundary {
            if let lastLine = lines.last, !lastLine.isEmpty {
                lines.append("")
            }
            statementBoundary = false
        }
        if !hasContent {
            currentIndent = pendingIndent
        }
        let space = hasContent && spacingBefore(token)
        lastTokenUnary = false
        if space {
            current += " "
        }
        current += text
        hasContent = true
        lastToken = token
    }

    private func spacingBefore(_ token: SQLToken) -> Bool {
        guard let previous = lastToken else {
            return false
        }
        return SQLFormatter.spacingBetween(previous, token, previousIsUnaryMinus: lastTokenUnary)
    }

    private mutating func emitWord(_ token: SQLToken) {
        if let clause = matchClause(at: index) {
            newline(indent: depth)
            for offset in 0 ..< clause.length {
                let word = tokens[index + offset]
                emit(word, text: word.text.uppercased())
            }
            index += clause.length - 1
            clauseIsBreakable = clause.breakable
            return
        }

        let upper = token.text.uppercased()
        switch upper {
        case "AND", "OR":
            if upper == "AND", pendingBetween {
                pendingBetween = false
                emit(token, text: upper)
            } else if clauseIsBreakable {
                newline(indent: depth + 1)
                emit(token, text: upper)
            } else {
                emit(token, text: upper)
            }
        case "BETWEEN":
            emit(token, text: upper)
            pendingBetween = true
        case "CASE":
            emit(token, text: upper)
            contexts.append(.caseBlock)
            clauseStack.append((clauseIsBreakable, pendingBetween))
            clauseIsBreakable = false
            pendingBetween = false
        case "WHEN":
            newline(indent: depth)
            emit(token, text: upper)
            clauseIsBreakable = true
        case "ELSE":
            newline(indent: depth)
            emit(token, text: upper)
            clauseIsBreakable = false
        case "THEN":
            emit(token, text: upper)
            clauseIsBreakable = false
        case "END":
            if case .caseBlock = contexts.last {
                contexts.removeLast()
                let saved = clauseStack.popLast()
                clauseIsBreakable = saved?.breakable ?? false
                pendingBetween = saved?.pendingBetween ?? false
            }
            newline(indent: depth)
            emit(token, text: upper)
        case "ON":
            emit(token, text: upper)
            clauseIsBreakable = true
        default:
            emit(token, text: SQLFormatter.stylizedWords.contains(upper) ? upper : token.text)
        }
    }

    private mutating func emitOpenParen(_ token: SQLToken) {
        let expanded = groupContainsClause(startingAt: index)
        emit(token, text: "(")
        contexts.append(.paren(expanded: expanded))
        clauseStack.append((clauseIsBreakable, pendingBetween))
        clauseIsBreakable = false
        pendingBetween = false
        if expanded {
            newline(indent: depth)
        }
    }

    private mutating func emitCloseParen(_ token: SQLToken) {
        var expanded = false
        if case .paren(let wasExpanded) = contexts.last {
            expanded = wasExpanded
            contexts.removeLast()
            let saved = clauseStack.popLast()
            clauseIsBreakable = saved?.breakable ?? false
            pendingBetween = saved?.pendingBetween ?? false
        }
        if expanded {
            newline(indent: depth)
        }
        emit(token, text: ")")
    }

    private mutating func emitLineComment(_ token: SQLToken) {
        if hasContent, !token.precededByNewline {
            current += " " + token.text
        } else {
            finishLine()
            if statementBoundary {
                if let lastLine = lines.last, !lastLine.isEmpty {
                    lines.append("")
                }
                statementBoundary = false
            }
            currentIndent = pendingIndent
            current = token.text
            hasContent = true
        }
        finishLine()
    }

    private mutating func emitBlockComment(_ token: SQLToken) {
        if !token.text.contains("\n") {
            emit(token, text: token.text)
            return
        }
        finishLine()
        for line in token.text.components(separatedBy: "\n") {
            lines.append(String(repeating: indentUnit, count: depth) + line)
        }
        pendingIndent = depth
    }

    private func matchClause(at start: Int) -> (length: Int, breakable: Bool)? {
        for phrase in SQLFormatter.clausePhrases {
            let words = phrase.words
            var matched = true
            for offset in 0 ..< words.count {
                let tokenIndex = start + offset
                guard tokenIndex < tokens.count,
                      tokens[tokenIndex].kind == .word,
                      tokens[tokenIndex].text.uppercased() == words[offset] else {
                    matched = false
                    break
                }
            }
            if matched {
                if words == ["WITH"], start + 1 < tokens.count, tokens[start + 1].kind == .openParen {
                    continue
                }
                return (words.count, phrase.breakable)
            }
        }
        return nil
    }

    private func groupContainsClause(startingAt openIndex: Int) -> Bool {
        var innerDepth = 0
        var cursor = openIndex + 1
        while cursor < tokens.count {
            let token = tokens[cursor]
            switch token.kind {
            case .openParen:
                innerDepth += 1
            case .closeParen:
                if innerDepth == 0 {
                    return false
                }
                innerDepth -= 1
            case .word where innerDepth == 0:
                let upper = token.text.uppercased()
                if matchClause(at: cursor) != nil || upper == "CASE" || upper == "WHEN" {
                    return true
                }
            default:
                break
            }
            cursor += 1
        }
        return false
    }

    private mutating func newline(indent: Int) {
        finishLine()
        pendingIndent = indent
    }

    private mutating func finishLine() {
        guard hasContent else {
            return
        }
        lines.append(String(repeating: indentUnit, count: currentIndent) + current)
        current = ""
        hasContent = false
        lastToken = nil
        lastTokenUnary = false
    }
}
