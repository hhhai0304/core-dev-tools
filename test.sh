#!/bin/zsh
set -euo pipefail
cd "${0:a:h}"

mkdir -p build/tests
swiftc -swift-version 5 \
  Sources/JSONCore.swift \
  Sources/URLCoding.swift \
  Sources/JSONArrayAligner.swift \
  Sources/SideBySideDiff.swift \
  Tests/main.swift \
  -o build/tests/json-core-tests

build/tests/json-core-tests

swiftc -swift-version 5 \
  Sources/JSONCodeEditor.swift \
  Tests/EditorPerformance/main.swift \
  -o build/tests/editor-performance-tests \
  -framework AppKit \
  -framework SwiftUI

build/tests/editor-performance-tests

swiftc -swift-version 5 \
  Sources/JSONCore.swift \
  Sources/JSONArrayAligner.swift \
  Sources/SideBySideDiff.swift \
  Sources/SelectableDiffComparisonView.swift \
  Tests/DiffSelection/main.swift \
  -o build/tests/diff-selection-tests \
  -framework AppKit \
  -framework SwiftUI

build/tests/diff-selection-tests
