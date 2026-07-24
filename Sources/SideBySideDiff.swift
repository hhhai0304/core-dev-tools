import Foundation

struct JSONSideBySideLine: Codable, Identifiable, Equatable {
    let id: Int
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let leftText: String?
    let rightText: String?
    let status: JSONDiffStatus
    let differenceID: Int?
}

struct JSONDifferenceAnchor: Codable, Identifiable, Equatable {
    let id: Int
    let path: String
    let status: JSONDiffStatus
    let lineID: Int
}

struct JSONSideBySideResult {
    let lines: [JSONSideBySideLine]
    let anchors: [JSONDifferenceAnchor]
}

enum JSONSideBySideDiffer {
    private struct DifferenceDescriptor {
        let id: Int
        let path: String
        let status: JSONDiffStatus
    }

    private struct AnnotatedLine {
        let alignmentKey: String
        let path: String
        let text: String
        let status: JSONDiffStatus
        let differenceID: Int?
        let lineNumber: Int
    }

    static func compare(_ left: JSONValue, _ right: JSONValue) -> JSONSideBySideResult {
        let differences = JSONDiffer.compare(left, right)
            .filter { $0.status != .unchanged }
            .enumerated()
            .map { offset, row in
                DifferenceDescriptor(id: offset, path: row.path, status: row.status)
            }
        let differenceByPath = Dictionary(uniqueKeysWithValues: differences.map { ($0.path, $0) })
        let reorderedRight = reorder(right, following: left)

        let leftLines = render(left, differences: differenceByPath)
        let rightLines = render(reorderedRight, differences: differenceByPath)
        let alignedLines = align(leftLines, rightLines)
        var firstLineByDifferenceID: [Int: Int] = [:]
        for line in alignedLines {
            if let differenceID = line.differenceID, firstLineByDifferenceID[differenceID] == nil {
                firstLineByDifferenceID[differenceID] = line.id
            }
        }

        let anchors = differences.compactMap { difference -> JSONDifferenceAnchor? in
            guard let lineID = firstLineByDifferenceID[difference.id] else {
                return nil
            }
            return JSONDifferenceAnchor(
                id: difference.id,
                path: difference.path,
                status: difference.status,
                lineID: lineID
            )
        }

        return JSONSideBySideResult(lines: alignedLines, anchors: anchors)
    }

    private static func reorder(_ value: JSONValue, following reference: JSONValue?) -> JSONValue {
        switch (value, reference) {
        case let (.object(entries), .object(referenceEntries)):
            let entryByKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
            let referenceByKey = Dictionary(uniqueKeysWithValues: referenceEntries.map { ($0.key, $0.value) })
            let referenceKeys = Set(referenceEntries.map(\.key))

            var orderedEntries = referenceEntries.compactMap { referenceEntry -> JSONObjectEntry? in
                guard let child = entryByKey[referenceEntry.key] else {
                    return nil
                }
                return JSONObjectEntry(
                    key: referenceEntry.key,
                    value: reorder(child, following: referenceEntry.value)
                )
            }

            orderedEntries.append(contentsOf: entries.compactMap { entry in
                guard !referenceKeys.contains(entry.key) else {
                    return nil
                }
                return JSONObjectEntry(
                    key: entry.key,
                    value: reorder(entry.value, following: referenceByKey[entry.key])
                )
            })
            return .object(orderedEntries)

        case let (.array(values), .array(referenceValues)):
            let alignment = JSONArrayAligner.align(left: referenceValues, right: values)
            return .array(alignment.map { pair in
                guard let rightIndex = pair.rightIndex else {
                    return .missing
                }
                let reference = pair.leftIndex.map { referenceValues[$0] }
                return reorder(values[rightIndex], following: reference)
            })

        default:
            return value
        }
    }

    private static func render(
        _ value: JSONValue,
        differences: [String: DifferenceDescriptor]
    ) -> [AnnotatedLine] {
        var lines: [AnnotatedLine] = []
        appendRenderedLines(
            value,
            path: "$",
            depth: 0,
            prefix: "",
            suffix: "",
            inheritedDifference: nil,
            differences: differences,
            to: &lines
        )
        return lines.enumerated().map { offset, line in
            AnnotatedLine(
                alignmentKey: line.alignmentKey,
                path: line.path,
                text: line.text,
                status: line.status,
                differenceID: line.differenceID,
                lineNumber: offset + 1
            )
        }
    }

    private static func appendRenderedLines(
        _ value: JSONValue,
        path: String,
        depth: Int,
        prefix: String,
        suffix: String,
        inheritedDifference: DifferenceDescriptor?,
        differences: [String: DifferenceDescriptor],
        to lines: inout [AnnotatedLine]
    ) {
        let difference = differences[path] ?? inheritedDifference
        let status = difference?.status ?? .unchanged
        let indentation = String(repeating: "  ", count: depth)

        switch value {
        case .missing:
            return

        case let .object(entries):
            lines.append(AnnotatedLine(
                alignmentKey: "\(path)|value",
                path: path,
                text: "\(indentation)\(prefix){",
                status: status,
                differenceID: difference?.id,
                lineNumber: 0
            ))

            for (index, entry) in entries.enumerated() {
                appendRenderedLines(
                    entry.value,
                    path: pathForKey(entry.key, parent: path),
                    depth: depth + 1,
                    prefix: "\(JSONRenderer.quotedString(entry.key)): ",
                    suffix: index < entries.count - 1 ? "," : "",
                    inheritedDifference: difference,
                    differences: differences,
                    to: &lines
                )
            }

            lines.append(AnnotatedLine(
                alignmentKey: "\(path)|end",
                path: path,
                text: "\(indentation)}\(suffix)",
                status: status,
                differenceID: difference?.id,
                lineNumber: 0
            ))

        case let .array(values):
            lines.append(AnnotatedLine(
                alignmentKey: "\(path)|value",
                path: path,
                text: "\(indentation)\(prefix)[",
                status: status,
                differenceID: difference?.id,
                lineNumber: 0
            ))

            let visibleChildren = values.enumerated().filter { _, child in
                child != .missing
            }
            for (position, indexedChild) in visibleChildren.enumerated() {
                let (alignedIndex, child) = indexedChild
                appendRenderedLines(
                    child,
                    path: "\(path)[\(alignedIndex)]",
                    depth: depth + 1,
                    prefix: "",
                    suffix: position < visibleChildren.count - 1 ? "," : "",
                    inheritedDifference: difference,
                    differences: differences,
                    to: &lines
                )
            }

            lines.append(AnnotatedLine(
                alignmentKey: "\(path)|end",
                path: path,
                text: "\(indentation)]\(suffix)",
                status: status,
                differenceID: difference?.id,
                lineNumber: 0
            ))

        default:
            lines.append(AnnotatedLine(
                alignmentKey: "\(path)|value",
                path: path,
                text: "\(indentation)\(prefix)\(JSONRenderer.minified(value))\(suffix)",
                status: status,
                differenceID: difference?.id,
                lineNumber: 0
            ))
        }
    }

    private static func align(
        _ leftLines: [AnnotatedLine],
        _ rightLines: [AnnotatedLine]
    ) -> [JSONSideBySideLine] {
        let leftPositions = Dictionary(uniqueKeysWithValues: leftLines.enumerated().map { ($0.element.alignmentKey, $0.offset) })
        let rightPositions = Dictionary(uniqueKeysWithValues: rightLines.enumerated().map { ($0.element.alignmentKey, $0.offset) })
        var output: [JSONSideBySideLine] = []
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < leftLines.count || rightIndex < rightLines.count {
            let left = leftIndex < leftLines.count ? leftLines[leftIndex] : nil
            let right = rightIndex < rightLines.count ? rightLines[rightIndex] : nil

            if let left, let right, left.alignmentKey == right.alignmentKey {
                output.append(makeLine(id: output.count, left: left, right: right))
                leftIndex += 1
                rightIndex += 1
                continue
            }

            if let left, rightPositions[left.alignmentKey] == nil {
                output.append(makeLine(id: output.count, left: left, right: nil))
                leftIndex += 1
                continue
            }

            if let right, leftPositions[right.alignmentKey] == nil {
                output.append(makeLine(id: output.count, left: nil, right: right))
                rightIndex += 1
                continue
            }

            if let left, let right,
               let leftPositionInRight = rightPositions[left.alignmentKey],
               let rightPositionInLeft = leftPositions[right.alignmentKey] {
                if leftPositionInRight - rightIndex <= rightPositionInLeft - leftIndex {
                    output.append(makeLine(id: output.count, left: nil, right: right))
                    rightIndex += 1
                } else {
                    output.append(makeLine(id: output.count, left: left, right: nil))
                    leftIndex += 1
                }
                continue
            }

            if let left {
                output.append(makeLine(id: output.count, left: left, right: nil))
                leftIndex += 1
            } else if let right {
                output.append(makeLine(id: output.count, left: nil, right: right))
                rightIndex += 1
            }
        }

        return output
    }

    private static func makeLine(
        id: Int,
        left: AnnotatedLine?,
        right: AnnotatedLine?
    ) -> JSONSideBySideLine {
        let status: JSONDiffStatus
        if let left, left.status != .unchanged {
            status = left.status
        } else if let right, right.status != .unchanged {
            status = right.status
        } else if left == nil {
            status = .added
        } else if right == nil {
            status = .removed
        } else {
            status = .unchanged
        }

        return JSONSideBySideLine(
            id: id,
            leftLineNumber: left?.lineNumber,
            rightLineNumber: right?.lineNumber,
            leftText: left?.text,
            rightText: right?.text,
            status: status,
            differenceID: left?.differenceID ?? right?.differenceID
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
