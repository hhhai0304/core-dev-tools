import Foundation

private func fail(_ message: String) -> Never {
    fputs("✗ \(message)\n", stderr)
    exit(1)
}

let itemCount = 25_000
let items = (0..<itemCount).map { index in
    "{\"id\":\(index),\"name\":\"item-\(index)\",\"active\":\(index.isMultiple(of: 2)),\"value\":null}"
}
let largeJSON = "[\(items.joined(separator: ","))]"

let start = CFAbsoluteTimeGetCurrent()
let tokens = JSONSyntaxHighlighter.tokenize(largeJSON)
let elapsed = CFAbsoluteTimeGetCurrent() - start

guard largeJSON.utf8.count > 1_000_000 else {
    fail("stress fixture should exceed 1 MB")
}
guard tokens.count > itemCount * 8 else {
    fail("syntax tokenizer returned too few tokens")
}
guard tokens.contains(where: { $0.kind == .key }),
      tokens.contains(where: { $0.kind == .string }),
      tokens.contains(where: { $0.kind == .number }),
      tokens.contains(where: { $0.kind == .keyword }) else {
    fail("syntax tokenizer missed one or more JSON token types")
}
guard elapsed < 5 else {
    fail("syntax tokenizer took \(String(format: "%.2f", elapsed)) seconds")
}

print("✓ tokenized \(largeJSON.utf8.count) bytes into \(tokens.count) tokens in \(String(format: "%.3f", elapsed))s")
