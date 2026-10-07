import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var keyboardMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            TabStrip()
            Divider()

            if let index = store.tabs.firstIndex(where: { $0.id == store.selectedTabID }) {
                TabContentView(tab: $store.tabs[index])
                    .id(store.tabs[index].id)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .preferredColorScheme(store.appearance.colorScheme)
        .onAppear(perform: installKeyboardMonitor)
        .onDisappear(perform: removeKeyboardMonitor)
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else {
            return
        }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let key = event.charactersIgnoringModifiers?.lowercased()

            if modifiers == .command, key == "t" {
                store.addHomeTab()
                return nil
            }
            if modifiers == .command, key == "w" {
                store.closeSelectedTab()
                return nil
            }
            if modifiers == .command, key == "f" {
                EditorFindAction.show()
                return nil
            }
            if modifiers == [.command, .shift], key == "[" {
                store.selectAdjacentTab(offset: -1)
                return nil
            }
            if modifiers == [.command, .shift], key == "]" {
                store.selectAdjacentTab(offset: 1)
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}

private struct TabStrip: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var draggedTabID: UUID?

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tabs) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: tab.id == store.selectedTabID,
                            onSelect: { store.selectedTabID = tab.id },
                            onClose: { store.closeTab(tab.id) }
                        )
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: TabDropDelegate(
                                targetTabID: tab.id,
                                draggedTabID: $draggedTabID,
                                store: store
                            )
                        )
                    }
                }
                .padding(.vertical, 7)
                .padding(.leading, 10)
            }

            Menu {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        store.appearance = appearance
                    } label: {
                        Label(
                            appearance.label,
                            systemImage: store.appearance == appearance ? "checkmark" : appearance.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: store.appearance.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help("Appearance: \(store.appearance.label)")

            Button(action: store.addHomeTab) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            .help("New tool tab (⌘T)")
            .padding(.trailing, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTabID: UUID
    @Binding var draggedTabID: UUID?
    let store: WorkspaceStore

    func dropEntered(info: DropInfo) {
        guard let draggedTabID,
              draggedTabID != targetTabID,
              let sourceIndex = store.tabs.firstIndex(where: { $0.id == draggedTabID }),
              let targetIndex = store.tabs.firstIndex(where: { $0.id == targetTabID }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            store.tabs.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }
}

private struct TabItem: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: tab.tool?.systemImage ?? "house")
                        .foregroundStyle(tab.tool?.tint ?? .secondary)
                    Text(tab.title)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 17, height: 17)
                    .background(Color.primary.opacity(0.001), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close tab · Middle-click anywhere on the tab")
        }
        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .overlay(MiddleClickCatcher(action: onClose))
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: MiddleClickView, context: Context) {
        view.action = action
    }
}

private final class MiddleClickView: NSView {
    var action: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .otherMouseDown,
              event.buttonNumber == 2,
              bounds.contains(point) else {
            return nil
        }
        return self
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            action?()
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct TabContentView: View {
    @Binding var tab: WorkspaceTab

    var body: some View {
        if let tool = tab.tool {
            switch tool {
            case .formatter:
                FormatterView(tab: $tab)
            case .sqlFormatter:
                SQLFormatterView(tab: $tab)
            case .diff:
                DiffView(tab: $tab)
            case .converter:
                ConverterView(tab: $tab)
            case .urlCoding:
                URLCodingView(tab: $tab)
            case .jwt:
                JWTView(tab: $tab)
            case .qrCode:
                QRCodeView(tab: $tab)
            }
        } else {
            HomeView(tabID: tab.id)
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let tabID: UUID

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Core Dev Tools")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Pick a developer tool. This Home tab will become its workspace.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(ToolKind.allCases) { tool in
                        Button {
                            store.selectTool(tool, in: tabID)
                        } label: {
                            ToolCard(tool: tool)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Label("Everything stays on this Mac. No network requests, analytics, or external dependencies.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.32))
    }
}

private struct ToolCard: View {
    let tool: ToolKind

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tool.tint)
                .frame(width: 44, height: 44)
                .background(tool.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 6) {
                Text(tool.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(tool.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}

private struct EditorPrimaryAction {
    let title: String
    let systemImage: String
    let action: () -> Void
}

private struct EditorPanel: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var supportsPaste = false
    var supportsCopy = true
    var primaryAction: EditorPrimaryAction?
    var secondaryAction: EditorPrimaryAction?
    var accessory: AnyView?
    var syntax: EditorSyntax = .json

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()

                if let accessory {
                    accessory
                }

                if let primaryAction {
                    Button(primaryAction.title, systemImage: primaryAction.systemImage) {
                        primaryAction.action()
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                }

                if let secondaryAction {
                    Button(secondaryAction.title, systemImage: secondaryAction.systemImage) {
                        secondaryAction.action()
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    EditorFindAction.show()
                } label: {
                    Label("Find (⌘F)", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Find in this editor")

                if supportsPaste {
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        if let clipboardText = Clipboard.read() {
                            text = clipboardText
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Paste from clipboard")
                }

                if supportsCopy {
                    Button("Copy", systemImage: "doc.on.doc") {
                        Clipboard.write(text)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(text.isEmpty)
                    .help("Copy to clipboard")
                }

                Button("Clear", systemImage: "xmark.circle") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(text.isEmpty)
                .help("Clear editor")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.035))

            Divider()

            ZStack(alignment: .topLeading) {
                CodeEditor(text: $text, syntax: syntax)

                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FormatterView: View {
    @Binding var tab: WorkspaceTab

    private var columns: [GridItem] {
        let count = tab.formatterEditors.count == 1 ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 320), spacing: 10),
            count: count
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach($tab.formatterEditors) { $editor in
                        let index = tab.formatterEditors.firstIndex(where: { $0.id == editor.id }) ?? 0
                        FormatterEditorPane(
                            editor: $editor,
                            number: index + 1,
                            canRemove: tab.formatterEditors.count > 1,
                            showsAddButton: index == tab.formatterEditors.count - 1,
                            onAdd: addEditor,
                            onRemove: { removeEditor(editor.id) }
                        )
                        .frame(height: paneHeight(availableHeight: geometry.size.height))
                    }
                }
                .padding(10)
            }
        }
    }

    private func paneHeight(availableHeight: CGFloat) -> CGFloat {
        let rowCount = max(1, (tab.formatterEditors.count + 1) / 2)
        if rowCount <= 2 {
            let gaps = CGFloat(rowCount - 1) * 10
            return max(260, (availableHeight - 20 - gaps) / CGFloat(rowCount))
        }
        return 300
    }

    private func addEditor() {
        tab.formatterEditors.append(.empty())
    }

    private func removeEditor(_ id: UUID) {
        guard tab.formatterEditors.count > 1 else {
            return
        }
        tab.formatterEditors.removeAll { $0.id == id }
    }
}

private struct FormatterEditorPane: View {
    @Binding var editor: JSONFormatterEditor
    let number: Int
    let canRemove: Bool
    let showsAddButton: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("Editor \(number)")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 4)

                Picker("Indent", selection: $editor.indentation) {
                    ForEach(Indentation.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)

                Button("Beautify", action: beautify)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Minify", action: minify)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                utilityButton("Find", systemImage: "magnifyingglass", action: EditorFindAction.show)
                utilityButton("Paste", systemImage: "doc.on.clipboard", action: paste)
                utilityButton("Copy", systemImage: "doc.on.doc", action: { Clipboard.write(editor.text) })
                    .disabled(editor.text.isEmpty)
                utilityButton("Clear", systemImage: "xmark.circle", action: clear)
                    .disabled(editor.text.isEmpty)

                if showsAddButton {
                    utilityButton("Add editor", systemImage: "plus.square", action: onAdd)
                }

                if canRemove {
                    utilityButton("Remove editor", systemImage: "trash", action: onRemove)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.primary.opacity(0.035))

            if let error = editor.errorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
            }

            Divider()

            ZStack(alignment: .topLeading) {
                CodeEditor(text: $editor.text)

                if editor.text.isEmpty {
                    Text("Paste JSON here…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
    }

    private func beautify() {
        do {
            editor.text = JSONRenderer.pretty(
                try parseJSON(editor.text),
                indentation: editor.indentation.value
            )
            editor.errorMessage = nil
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }

    private func minify() {
        do {
            editor.text = JSONRenderer.minified(try parseJSON(editor.text))
            editor.errorMessage = nil
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }

    private func paste() {
        if let clipboardText = Clipboard.read() {
            editor.text = clipboardText
            editor.errorMessage = nil
        }
    }

    private func clear() {
        editor.text = ""
        editor.errorMessage = nil
    }

    private func utilityButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(title)
    }
}

private struct ConverterView: View {
    @Binding var tab: WorkspaceTab

    var body: some View {
        VStack(spacing: 10) {
            if let error = tab.errorMessage {
                ErrorBanner(message: error)
            }
            HSplitView {
                EditorPanel(
                    title: "JSON",
                    placeholder: "Paste JSON here…",
                    text: $tab.primaryInput,
                    supportsPaste: true,
                    primaryAction: EditorPrimaryAction(
                        title: "To String",
                        systemImage: "arrow.right",
                        action: convertToString
                    )
                )
                .frame(minWidth: 360)
                EditorPanel(
                    title: "JSON String Literal",
                    placeholder: "Example: \"{\\\"name\\\":\\\"Ada\\\"}\"",
                    text: $tab.output,
                    supportsPaste: true,
                    primaryAction: EditorPrimaryAction(
                        title: "To JSON",
                        systemImage: "arrow.left",
                        action: convertToJSON
                    )
                )
                .frame(minWidth: 360)
            }
        }
        .padding(10)
    }

    private func convertToString() {
        do {
            let input = tab.primaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try parseJSON(input)
            tab.output = JSONRenderer.quotedString(input)
            tab.errorMessage = nil
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }

    private func convertToJSON() {
        do {
            let outer = try parseJSON(tab.output.trimmingCharacters(in: .whitespacesAndNewlines))
            guard case let .string(inner) = outer else {
                throw ConversionError.expectedString
            }
            let decoded = try parseJSON(inner)
            tab.primaryInput = JSONRenderer.pretty(decoded, indentation: Indentation.twoSpaces.value)
            tab.errorMessage = nil
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }
}

private struct URLCodingView: View {
    @Binding var tab: WorkspaceTab

    var body: some View {
        VStack(spacing: 10) {
            if let error = tab.errorMessage {
                ErrorBanner(message: error)
            }
            HSplitView {
                EditorPanel(
                    title: "Decoded URL / Text",
                    placeholder: "Paste a URL or text to encode…",
                    text: $tab.primaryInput,
                    supportsPaste: true,
                    primaryAction: EditorPrimaryAction(
                        title: "Encode",
                        systemImage: "arrow.right",
                        action: encode
                    )
                )
                .frame(minWidth: 360)
                EditorPanel(
                    title: "URL Encoded",
                    placeholder: "Example: https%3A%2F%2Fexample.com%2Fhello%20world",
                    text: $tab.output,
                    supportsPaste: true,
                    primaryAction: EditorPrimaryAction(
                        title: "Decode",
                        systemImage: "arrow.left",
                        action: decode
                    )
                )
                .frame(minWidth: 360)
            }
        }
        .padding(10)
    }

    private func encode() {
        tab.output = URLCoding.encode(tab.primaryInput)
        tab.errorMessage = nil
    }

    private func decode() {
        do {
            tab.primaryInput = try URLCoding.decode(tab.output)
            tab.errorMessage = nil
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }
}

private struct SQLFormatterView: View {
    @Binding var tab: WorkspaceTab

    var body: some View {
        VStack(spacing: 10) {
            if let error = tab.errorMessage {
                ErrorBanner(message: error)
            }
            EditorPanel(
                title: "SQL",
                placeholder: "Paste SQL here…",
                text: $tab.primaryInput,
                supportsPaste: true,
                primaryAction: EditorPrimaryAction(
                    title: "Beautify",
                    systemImage: "rectangle.expand.vertical",
                    action: beautify
                ),
                secondaryAction: EditorPrimaryAction(
                    title: "Minify",
                    systemImage: "rectangle.compress.vertical",
                    action: minify
                ),
                accessory: AnyView(indentationPicker),
                syntax: .sql
            )
        }
        .padding(10)
    }

    private var indentationPicker: some View {
        Picker("Indent", selection: $tab.sqlIndentation) {
            ForEach(Indentation.allCases) { style in
                Text(style.label).tag(style)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 92)
    }

    private func beautify() {
        do {
            tab.primaryInput = try SQLFormatter.beautify(
                tab.primaryInput,
                indentation: tab.sqlIndentation.value
            )
            tab.errorMessage = nil
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }

    private func minify() {
        do {
            tab.primaryInput = try SQLFormatter.minify(tab.primaryInput)
            tab.errorMessage = nil
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }
}

private struct DiffView: View {
    @Binding var tab: WorkspaceTab

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                if let error = tab.errorMessage {
                    ErrorBanner(message: error)
                }

                HSplitView {
                    EditorPanel(title: "JSON 1 · Base order", placeholder: "Paste the base JSON here…", text: $tab.primaryInput, supportsPaste: true)
                        .frame(minWidth: 360)
                    EditorPanel(
                        title: "JSON 2 · Comparison",
                        placeholder: "Paste the comparison JSON here…",
                        text: $tab.secondaryInput,
                        supportsPaste: true,
                        primaryAction: EditorPrimaryAction(
                            title: "Compare",
                            systemImage: "arrow.left.arrow.right",
                            action: compare
                        )
                    )
                    .frame(minWidth: 360)
                }
            }
            .padding(10)

            if tab.isShowingDiffComparison {
                DiffComparisonView(
                    lines: tab.diffLines,
                    anchors: tab.diffAnchors,
                    onEditInputs: { tab.isShowingDiffComparison = false }
                )
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(1)
            }
        }
    }

    private func compare() {
        do {
            let left = try parseJSON(tab.primaryInput)
            let right = try parseJSON(tab.secondaryInput)
            let result = JSONSideBySideDiffer.compare(left, right)
            tab.diffLines = result.lines
            tab.diffAnchors = result.anchors
            tab.errorMessage = nil
            EditorFindAction.deactivate()
            tab.isShowingDiffComparison = true
        } catch {
            tab.diffLines = []
            tab.diffAnchors = []
            tab.isShowingDiffComparison = false
            tab.errorMessage = error.localizedDescription
        }
    }
}

private struct DiffComparisonView: View {
    let lines: [JSONSideBySideLine]
    let anchors: [JSONDifferenceAnchor]
    let onEditInputs: () -> Void
    @State private var currentDifference = 0

    private var currentAnchor: JSONDifferenceAnchor? {
        guard anchors.indices.contains(currentDifference) else {
            return nil
        }
        return anchors[currentDifference]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Edit Inputs", systemImage: "chevron.left", action: onEditInputs)
                    .controlSize(.small)

                Divider()
                    .frame(height: 18)

                if anchors.isEmpty {
                    Label("No differences", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(anchors.count) differences")
                        .font(.subheadline.weight(.semibold))

                    ForEach([JSONDiffStatus.changed, .added, .removed], id: \.self) { status in
                        let count = anchors.filter { $0.status == status }.count
                        if count > 0 {
                            StatusBadge(status: status, count: count)
                        }
                    }
                }

                Spacer()

                if let currentAnchor {
                    Text(currentAnchor.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(currentAnchor.status.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(currentAnchor.path)

                    Button {
                        moveDifference(by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Previous difference")

                    Text("\(currentDifference + 1) / \(anchors.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        moveDifference(by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help("Next difference")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(Color.primary.opacity(0.035))

            Divider()

            HStack(spacing: 0) {
                Text("JSON 1 · Base order")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Text("JSON 2 · Reordered to match JSON 1")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.primary.opacity(0.025))

            Divider()

            SelectableDiffComparisonView(
                lines: lines,
                selectedDifferenceID: currentAnchor?.id,
                selectedLineID: currentAnchor?.lineID
            )
        }
    }

    private func moveDifference(by offset: Int) {
        guard !anchors.isEmpty else {
            return
        }
        currentDifference = (currentDifference + offset + anchors.count) % anchors.count
    }
}

private struct StatusBadge: View {
    let status: JSONDiffStatus
    let count: Int

    var body: some View {
        Text("\(status.label) \(count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.1), in: Capsule())
    }
}

private extension JSONDiffStatus {
    var color: Color {
        switch self {
        case .unchanged:
            return .secondary
        case .changed:
            return .orange
        case .added:
            return .green
        case .removed:
            return .red
        }
    }
}

private struct JWTView: View {
    @Binding var tab: WorkspaceTab

    private var timestamps: [JWTClaimTimestamp] {
        guard let payload = try? parseJSON(tab.secondaryInput) else {
            return []
        }
        return JWTDecoder.timestamps(in: payload)
    }

    private var signature: String? {
        guard let signature = JWTDecoder.signatureSegment(of: tab.primaryInput),
              !signature.isEmpty else {
            return nil
        }
        return signature
    }

    var body: some View {
        VStack(spacing: 10) {
            if let error = tab.errorMessage {
                ErrorBanner(message: error)
            }
            HSplitView {
                EditorPanel(
                    title: "JWT Token",
                    placeholder: "Paste a JWT here…",
                    text: $tab.primaryInput,
                    supportsPaste: true,
                    primaryAction: EditorPrimaryAction(
                        title: "Decode",
                        systemImage: "key",
                        action: decode
                    )
                )
                .frame(minWidth: 340)

                VStack(spacing: 10) {
                    VSplitView {
                        EditorPanel(
                            title: "Header",
                            placeholder: "Decoded header appears here…",
                            text: $tab.output
                        )
                        .frame(minHeight: 160)
                        EditorPanel(
                            title: "Payload",
                            placeholder: "Decoded payload appears here…",
                            text: $tab.secondaryInput
                        )
                        .frame(minHeight: 160)
                    }

                    if !timestamps.isEmpty || signature != nil {
                        decodedFooter
                    }
                }
                .frame(minWidth: 400)
            }
        }
        .padding(10)
    }

    private var decodedFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(timestamps) { claim in
                HStack(spacing: 8) {
                    Text(claim.name)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(claimColor(claim))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(claimColor(claim).opacity(0.12), in: Capsule())
                    Text(claim.date, format: .dateTime.year().month().day().hour().minute().second())
                        .font(.callout)
                    Text(relativeDescription(claim))
                        .font(.callout)
                        .foregroundStyle(claimColor(claim))
                }
            }

            if let signature {
                HStack(spacing: 8) {
                    Text("Signature")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(signature)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button("Copy signature", systemImage: "doc.on.doc") {
                        Clipboard.write(signature)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy signature")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
    }

    private func claimColor(_ claim: JWTClaimTimestamp) -> Color {
        guard claim.name == "exp" else {
            return .secondary
        }
        return claim.isPast ? .red : .green
    }

    private func relativeDescription(_ claim: JWTClaimTimestamp) -> String {
        let relative = claim.date.formatted(.relative(presentation: .named))
        guard claim.name == "exp" else {
            return relative
        }
        return claim.isPast ? "expired \(relative)" : "expires \(relative)"
    }

    private func decode() {
        do {
            let decoded = try JWTDecoder.decode(tab.primaryInput)
            tab.output = JSONRenderer.pretty(decoded.header, indentation: Indentation.twoSpaces.value)
            tab.secondaryInput = JSONRenderer.pretty(decoded.payload, indentation: Indentation.twoSpaces.value)
            tab.errorMessage = nil
        } catch {
            tab.errorMessage = error.localizedDescription
        }
    }
}

private struct QRCodeView: View {
    @Binding var tab: WorkspaceTab
    @State private var mode: Mode = .generate
    @State private var correctionLevel: QRCodeLevel = .medium
    @State private var generatedImage: NSImage?
    @State private var decodedImage: NSImage?
    @State private var isDropTargeted = false

    private enum Mode {
        case generate
        case decode
    }

    private var matches: [QRCodeMatch] {
        guard let data = tab.output.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([QRCodeMatch].self, from: data) else {
            return []
        }
        return decoded
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Mode", selection: $mode) {
                    Text("Generate").tag(Mode.generate)
                    Text("Decode").tag(Mode.decode)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()
            }

            if let error = tab.errorMessage {
                ErrorBanner(message: error)
            }

            switch mode {
            case .generate:
                generateView
            case .decode:
                decodeView
            }
        }
        .padding(10)
        .onAppear {
            restoreDecodedImage()
            if generatedImage == nil, !tab.primaryInput.isEmpty {
                generate()
            }
        }
    }

    private var generateView: some View {
        HSplitView {
            EditorPanel(
                title: "Text",
                placeholder: "Type or paste the text to encode…",
                text: $tab.primaryInput,
                supportsPaste: true,
                primaryAction: EditorPrimaryAction(
                    title: "Generate",
                    systemImage: "qrcode",
                    action: generate
                )
            )
            .frame(minWidth: 340)

            VStack(spacing: 0) {
                HStack {
                    Text("QR Code")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Picker("Error correction", selection: Binding(
                        get: { correctionLevel },
                        set: { level in
                            correctionLevel = level
                            if generatedImage != nil {
                                generate()
                            }
                        }
                    )) {
                        ForEach(QRCodeLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .help("Error correction level")

                    Button("Copy image", systemImage: "doc.on.doc", action: copyGeneratedImage)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(generatedImage == nil)
                        .help("Copy QR image")

                    Button("Save image…", systemImage: "square.and.arrow.down", action: saveGeneratedImage)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(generatedImage == nil)
                        .help("Save QR code as PNG…")
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.primary.opacity(0.035))

                Divider()

                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    if let generatedImage {
                        Image(nsImage: generatedImage)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .padding(24)
                    } else {
                        Text("Generate a QR code to preview it here")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
            .frame(minWidth: 340)
        }
    }

    private var decodeView: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Image")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button("Decode", systemImage: "qrcode.viewfinder", action: decodeImage)
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(tab.secondaryInput.isEmpty)

                    Button("Open image…", systemImage: "folder", action: openImage)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open an image file…")

                    Button("Paste image", systemImage: "doc.on.clipboard", action: pasteImage)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Paste an image from the clipboard")

                    Button("Clear", systemImage: "xmark.circle", action: clearImage)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(tab.secondaryInput.isEmpty)
                        .help("Clear image and results")
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.primary.opacity(0.035))

                Divider()

                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    if let decodedImage {
                        Image(nsImage: decodedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 30))
                                .foregroundStyle(.tertiary)
                            Text("Drop an image here, paste from the clipboard, or open a file")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
            .frame(minWidth: 340)

            VStack(spacing: 0) {
                HStack {
                    Text("Decoded Content")
                        .font(.subheadline.weight(.semibold))
                    if !matches.isEmpty {
                        Text("\(matches.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }

                    Spacer()

                    Button("Copy all", systemImage: "doc.on.doc") {
                        Clipboard.write(matches.map(\.message).joined(separator: "\n"))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(matches.isEmpty)
                    .help("Copy all decoded values")
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.primary.opacity(0.035))

                Divider()

                if matches.isEmpty {
                    Text("Load an image to decode every QR code it contains")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                        .background(Color(nsColor: .textBackgroundColor))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Color.accentColor, in: Circle())
                                    Text(match.message)
                                        .font(.callout.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button("Copy", systemImage: "doc.on.doc") {
                                        Clipboard.write(match.message)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .help("Copy value")
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(10)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
            .frame(minWidth: 340)
        }
    }

    private func generate() {
        guard !tab.primaryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            tab.errorMessage = "Enter some text to encode as a QR code."
            return
        }
        guard let image = QRCodeGenerator.image(message: tab.primaryInput, correctionLevel: correctionLevel) else {
            tab.errorMessage = "Couldn't generate a QR code for this input."
            return
        }
        generatedImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        tab.errorMessage = nil
    }

    private func copyGeneratedImage() {
        guard let generatedImage else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([generatedImage])
    }

    private func saveGeneratedImage() {
        guard let generatedImage,
              let cgImage = QRImageConversion.cgImage(from: generatedImage),
              let png = QRImageConversion.pngData(from: cgImage) else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qrcode.png"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try png.write(to: url)
        } catch {
            tab.errorMessage = "Couldn't save the image: \(error.localizedDescription)"
        }
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            guard let image = QRImageConversion.cgImage(from: try Data(contentsOf: url)) else {
                tab.errorMessage = "\(url.lastPathComponent) isn't a readable image."
                return
            }
            setImage(image)
        } catch {
            tab.errorMessage = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func pasteImage() {
        guard let image = QRImageConversion.cgImageFromPasteboard() else {
            tab.errorMessage = "The clipboard doesn't contain an image."
            return
        }
        setImage(image)
    }

    private func clearImage() {
        tab.secondaryInput = ""
        tab.output = ""
        decodedImage = nil
        tab.errorMessage = nil
    }

    private func setImage(_ image: CGImage) {
        tab.secondaryInput = QRImageConversion.base64PNG(from: image) ?? ""
        decodeImage()
    }

    private func decodeImage() {
        guard let source = QRImageConversion.cgImage(fromBase64PNG: tab.secondaryInput) else {
            tab.errorMessage = "Load an image before decoding."
            return
        }
        let found = QRCodeReader.decode(source)
        if let encoded = try? JSONEncoder().encode(found) {
            tab.output = String(decoding: encoded, as: UTF8.self)
        }
        decodedImage = QRImageAnnotator.annotated(source: source, matches: found)
        tab.errorMessage = found.isEmpty ? "No QR codes found in this image." : nil
    }

    private func restoreDecodedImage() {
        guard let source = QRImageConversion.cgImage(fromBase64PNG: tab.secondaryInput) else {
            decodedImage = nil
            return
        }
        decodedImage = QRImageAnnotator.annotated(source: source, matches: matches)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let image = QRImageConversion.cgImage(from: data) else {
                    return
                }
                DispatchQueue.main.async {
                    setImage(image)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap {
                    URL(dataRepresentation: $0, relativeTo: nil)
                }
                guard let url,
                      let data = try? Data(contentsOf: url),
                      let image = QRImageConversion.cgImage(from: data) else {
                    return
                }
                DispatchQueue.main.async {
                    setImage(image)
                }
            }
            return true
        }

        return false
    }
}

private enum Clipboard {
    static func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func write(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private enum ConversionError: LocalizedError {
    case expectedString

    var errorDescription: String? {
        "Input must be a quoted JSON string literal, such as \"{\\\"name\\\":\\\"Ada\\\"}\"."
    }
}
