import AppKit

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        failures += 1
        print("✗ \(message)")
    }
}

private func textViews(in view: NSView) -> [NSTextView] {
    view.subviews.flatMap { child in
        (child as? NSTextView).map { [$0] } ?? textViews(in: child)
    }
}

_ = NSApplication.shared

let lines = [
    JSONSideBySideLine(
        id: 0,
        leftLineNumber: 1,
        rightLineNumber: 1,
        leftText: "alpha",
        rightText: "one",
        status: .unchanged,
        differenceID: nil
    ),
    JSONSideBySideLine(
        id: 1,
        leftLineNumber: 2,
        rightLineNumber: 2,
        leftText: "beta",
        rightText: "two",
        status: .changed,
        differenceID: 0
    ),
    JSONSideBySideLine(
        id: 2,
        leftLineNumber: 3,
        rightLineNumber: 3,
        leftText: "gamma",
        rightText: "three",
        status: .unchanged,
        differenceID: nil
    ),
]

let comparison = DiffComparisonScrollContainer(
    frame: NSRect(x: 0, y: 0, width: 900, height: 500)
)
comparison.update(lines: lines, selectedDifferenceID: 0, selectedLineID: 1)
comparison.layoutSubtreeIfNeeded()

guard let leftTextView = textViews(in: comparison).first(where: {
    $0.string.contains("alpha\nbeta\ngamma")
}) else {
    print("✗ diff comparison exposes a continuous selectable text view")
    exit(1)
}

let source = leftTextView.string as NSString
let selection = source.range(of: "alpha\nbeta")
leftTextView.setSelectedRange(selection)

check(selection.location != NSNotFound, "diff side stores rendered rows as continuous text")
check(leftTextView.selectedRange() == selection, "selection can span multiple rendered rows")
check(source.substring(with: leftTextView.selectedRange()) == "alpha\nbeta", "multi-line selection preserves copyable plain text")

let largeLines = (0..<10_000).map { index in
    JSONSideBySideLine(
        id: index,
        leftLineNumber: index + 1,
        rightLineNumber: index + 1,
        leftText: "  \"key\(index)\": \(index),",
        rightText: "  \"key\(index)\": \(index),",
        status: .unchanged,
        differenceID: nil
    )
}
let largeComparison = DiffComparisonScrollContainer(
    frame: NSRect(x: 0, y: 0, width: 900, height: 500)
)
let layoutStart = CFAbsoluteTimeGetCurrent()
largeComparison.update(lines: largeLines, selectedDifferenceID: nil, selectedLineID: nil)
largeComparison.layoutSubtreeIfNeeded()
let layoutElapsed = CFAbsoluteTimeGetCurrent() - layoutStart
check(layoutElapsed < 5, "continuous diff text remains responsive with 10,000 rendered rows")
print("  diff selection layout: 10000 rows in \(String(format: "%.3f", layoutElapsed))s")

if failures > 0 {
    print("\n\(failures) diff selection test(s) failed.")
    exit(1)
}

print("\nAll diff selection tests passed.")
