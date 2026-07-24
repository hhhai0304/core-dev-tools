import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        failures += 1
        print("✗ \(message)")
    }
}

private func checkThrows(_ message: String, _ operation: () throws -> Void) {
    do {
        try operation()
        failures += 1
        print("✗ \(message)")
    } catch {
        print("✓ \(message)")
    }
}

do {
    let source = """
    {"z":1,"name":"Ada","nested":{"b":true,"a":null},"emoji":"\\uD83D\\uDE80"}
    """
    let value = try parseJSON(source)
    let pretty = JSONRenderer.pretty(value, indentation: "  ")
    let minified = JSONRenderer.minified(value)

    check(pretty.hasPrefix("{\n  \"z\": 1,"), "beautify preserves source key order")
    check(minified == "{\"z\":1,\"name\":\"Ada\",\"nested\":{\"b\":true,\"a\":null},\"emoji\":\"🚀\"}", "minify preserves values and emits valid Unicode")
    let reparsed = try parseJSON(minified)
    check(reparsed == value, "rendered JSON parses back to the same value")

    let tabbed = JSONRenderer.pretty(value, indentation: "\t")
    check(tabbed.contains("\n\t\"z\""), "tab indentation is supported")
} catch {
    failures += 1
    print("✗ formatter tests threw: \(error)")
}

do {
    let left = try parseJSON("{\"b\":2,\"a\":1,\"nested\":{\"x\":true},\"items\":[1,2]}")
    let right = try parseJSON("{\"a\":9,\"b\":2,\"nested\":{\"x\":true,\"y\":false},\"items\":[1,3],\"extra\":null}")
    let rows = JSONDiffer.compare(left, right)

    check(rows.map(\.path) == ["$.b", "$.a", "$.nested.x", "$.nested.y", "$.items[0]", "$.items[1]", "$.extra"], "diff rows follow JSON 1 key order and append JSON 2-only keys")
    check(rows.first(where: { $0.path == "$.a" })?.status == .changed, "changed values are detected by key")
    check(rows.first(where: { $0.path == "$.nested.y" })?.status == .added, "nested additions are detected")
    check(rows.first(where: { $0.path == "$.items[1]" })?.status == .changed, "arrays are compared by index")
    check(rows.first(where: { $0.path == "$.b" })?.status == .unchanged, "unchanged values are retained for side-by-side alignment")
} catch {
    failures += 1
    print("✗ diff tests threw: \(error)")
}

do {
    let left = try parseJSON("{\"b\":2,\"a\":1,\"removed\":true,\"nested\":{\"x\":1}}")
    let right = try parseJSON("{\"nested\":{\"x\":2,\"extra\":null},\"a\":9,\"b\":2}")
    let comparison = JSONSideBySideDiffer.compare(left, right)
    let rightText = comparison.lines.compactMap(\.rightText).joined(separator: "\n")

    check(comparison.anchors.count == 4, "side-by-side diff counts changed, added, and removed paths")
    check(rightText.range(of: "\"b\": 2")!.lowerBound < rightText.range(of: "\"a\": 9")!.lowerBound, "JSON 2 is reordered to follow JSON 1")
    check(comparison.anchors.map(\.path) == ["$.a", "$.removed", "$.nested.x", "$.nested.extra"], "diff navigation anchors follow display order")

    if let removedAnchor = comparison.anchors.first(where: { $0.status == .removed }),
       let removedLine = comparison.lines.first(where: { $0.id == removedAnchor.lineID }) {
        check(removedLine.leftText?.contains("\"removed\"") == true && removedLine.rightText == nil, "removed values align with an empty JSON 2 line")
    } else {
        failures += 1
        print("✗ removed side-by-side anchor exists")
    }
} catch {
    failures += 1
    print("✗ side-by-side diff tests threw: \(error)")
}

do {
    let left = try parseJSON("""
    {"items":[
      {"label":"Draft","codes":["DRAFT"]},
      {"label":"In review","codes":["IN_REVIEW"]},
      {"label":"Rejected","codes":["REJECTED"]},
      {"label":"Approved","codes":["APPROVED"]},
      {"label":"Published","codes":["PUBLISHED"]}
    ]}
    """)
    let right = try parseJSON("""
    {"items":[
      {"label":"Draft","codes":["DRAFT"]},
      {"label":"Rejected","codes":["REJECTED"]},
      {"label":"Approved","codes":["APPROVED"]},
      {"label":"Published","codes":["PUBLISHED"]}
    ]}
    """)
    let changedRows = JSONDiffer.compare(left, right).filter { $0.status != .unchanged }
    let comparison = JSONSideBySideDiffer.compare(left, right)

    check(changedRows.count == 1, "object-array insertion creates one diff instead of cascading changes")
    check(changedRows.first?.path == "$.items[1]" && changedRows.first?.status == .removed, "array-valued identity locates the inserted object")
    check(comparison.anchors.count == 1, "side-by-side navigation contains one anchor for the inserted object")

    if let insertedLine = comparison.lines.first(where: {
        $0.leftText?.contains("In review") == true
    }) {
        check(insertedLine.status == .removed && insertedLine.rightText == nil, "inserted object is highlighted against an empty opposite line")
    } else {
        failures += 1
        print("✗ inserted object is rendered in side-by-side diff")
    }

    let rejectedLines = comparison.lines.filter {
        $0.leftText?.contains("Rejected") == true || $0.rightText?.contains("Rejected") == true
    }
    check(rejectedLines.count == 1 && rejectedLines[0].status == .unchanged && rejectedLines[0].leftText != nil && rejectedLines[0].rightText != nil, "objects after an insertion remain aligned and unchanged")
} catch {
    failures += 1
    print("✗ object-array insertion regression test threw: \(error)")
}

do {
    let itemCount = 10_000
    let leftText = "{" + (0..<itemCount).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}"
    let rightText = "{" + (0..<itemCount).reversed().map { index in
        "\"k\(index)\":\(index.isMultiple(of: 10) ? index + 1 : index)"
    }.joined(separator: ",") + "}"
    let start = CFAbsoluteTimeGetCurrent()
    let comparison = JSONSideBySideDiffer.compare(try parseJSON(leftText), try parseJSON(rightText))
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    check(comparison.anchors.count == itemCount / 10, "large side-by-side diff counts every changed key")
    check(elapsed < 5, "large side-by-side diff remains linear enough for interactive use")
    print("  side-by-side stress: \(itemCount) keys in \(String(format: "%.3f", elapsed))s")
} catch {
    failures += 1
    print("✗ side-by-side stress test threw: \(error)")
}

do {
    let rawJSON = "{\n  \"message\": \"hello\"\n}"
    let stringLiteral = JSONRenderer.quotedString(rawJSON)
    let outerValue = try parseJSON(stringLiteral)
    if case let .string(decoded) = outerValue {
        check(decoded == rawJSON, "JSON to string and string to JSON round-trip")
        let decodedValue = try parseJSON(decoded)
        let originalValue = try parseJSON(rawJSON)
        check(decodedValue == originalValue, "decoded string contains valid JSON")
    } else {
        failures += 1
        print("✗ quoted output is a JSON string")
    }
} catch {
    failures += 1
    print("✗ conversion tests threw: \(error)")
}

do {
    let decoded = "https://example.com/a path?q=hello world&emoji=🚀"
    let encoded = "https%3A%2F%2Fexample.com%2Fa%20path%3Fq%3Dhello%20world%26emoji%3D%F0%9F%9A%80"
    let roundTripped = try URLCoding.decode(encoded)
    let plusDecoded = try URLCoding.decode("a+b%2Bc")

    check(URLCoding.encode(decoded) == encoded, "URL encoding uses UTF-8 RFC 3986 percent escapes")
    check(roundTripped == decoded, "URL encode and decode round-trip")
    check(plusDecoded == "a+b+c", "URL decoding preserves literal plus signs")
} catch {
    failures += 1
    print("✗ URL coding tests threw: \(error)")
}

checkThrows("malformed URL percent escapes are rejected") {
    _ = try URLCoding.decode("hello%2world")
}

checkThrows("URL percent escapes must decode to valid UTF-8") {
    _ = try URLCoding.decode("%FF")
}

checkThrows("duplicate object keys are rejected for exact diffing") {
    _ = try parseJSON("{\"id\":1,\"id\":2}")
}

checkThrows("invalid JSON numbers are rejected") {
    _ = try parseJSON("{\"value\":01}")
}

if failures > 0 {
    print("\n\(failures) test(s) failed.")
    exit(1)
}

print("\nAll core tests passed.")
