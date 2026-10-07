import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case formatter
    case sqlFormatter
    case diff
    case converter
    case urlCoding
    case jwt
    case qrCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formatter:
            return "JSON Formatter"
        case .sqlFormatter:
            return "SQL Formatter"
        case .diff:
            return "JSON Diff"
        case .converter:
            return "JSON ↔ String"
        case .urlCoding:
            return "URL Encode ↔ Decode"
        case .jwt:
            return "JWT Decoder"
        case .qrCode:
            return "QR Code"
        }
    }

    var subtitle: String {
        switch self {
        case .formatter:
            return "Beautify or minify in place across multiple editors."
        case .sqlFormatter:
            return "Beautify or minify SQL queries in place."
        case .diff:
            return "Compare by key and JSON path, aligned to JSON 1 order."
        case .converter:
            return "Convert in either direction between JSON and a JSON string literal."
        case .urlCoding:
            return "Percent-encode or decode URLs and text in either direction."
        case .jwt:
            return "Decode a JWT's header, payload, and timestamp claims."
        case .qrCode:
            return "Generate QR codes from text, or decode every QR in an image."
        }
    }

    var systemImage: String {
        switch self {
        case .formatter:
            return "curlybraces.square"
        case .sqlFormatter:
            return "cylinder.split.1x2"
        case .diff:
            return "arrow.left.arrow.right"
        case .converter:
            return "arrow.left.arrow.right.square"
        case .urlCoding:
            return "link"
        case .jwt:
            return "key.fill"
        case .qrCode:
            return "qrcode"
        }
    }

    var tint: Color {
        switch self {
        case .formatter:
            return .blue
        case .sqlFormatter:
            return .teal
        case .diff:
            return .orange
        case .converter:
            return .green
        case .urlCoding:
            return .purple
        case .jwt:
            return .pink
        case .qrCode:
            return .indigo
        }
    }
}

enum Indentation: String, Codable, CaseIterable, Identifiable {
    case twoSpaces
    case fourSpaces
    case tab

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twoSpaces:
            return "2 Spaces"
        case .fourSpaces:
            return "4 Spaces"
        case .tab:
            return "Tab"
        }
    }

    var value: String {
        switch self {
        case .twoSpaces:
            return "  "
        case .fourSpaces:
            return "    "
        case .tab:
            return "\t"
        }
    }
}

struct JSONFormatterEditor: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var indentation: Indentation
    var errorMessage: String?

    static func empty() -> JSONFormatterEditor {
        JSONFormatterEditor(
            id: UUID(),
            text: "",
            indentation: .twoSpaces,
            errorMessage: nil
        )
    }
}

struct WorkspaceTab: Codable, Identifiable, Equatable {
    let id: UUID
    var tool: ToolKind?
    var sequence: Int
    var primaryInput: String
    var secondaryInput: String
    var output: String
    var formatterEditors: [JSONFormatterEditor]
    var sqlIndentation: Indentation
    var diffLines: [JSONSideBySideLine]
    var diffAnchors: [JSONDifferenceAnchor]
    var isShowingDiffComparison: Bool
    var errorMessage: String?

    var title: String {
        guard let tool else {
            return "Home"
        }
        return "\(tool.title) #\(sequence)"
    }

    static func home() -> WorkspaceTab {
        WorkspaceTab(
            id: UUID(),
            tool: nil,
            sequence: 0,
            primaryInput: "",
            secondaryInput: "",
            output: "",
            formatterEditors: [.empty(), .empty()],
            sqlIndentation: .twoSpaces,
            diffLines: [],
            diffAnchors: [],
            isShowingDiffComparison: false,
            errorMessage: nil
        )
    }
}

final class WorkspaceStore: ObservableObject {
    @Published var tabs: [WorkspaceTab]
    @Published var selectedTabID: UUID

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    private static let appearanceKey = "CoreDevToolsAppearance"

    init() {
        let home = WorkspaceTab.home()
        tabs = [home]
        selectedTabID = home.id
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system

        // Version 1 persisted full editor contents. The app now always starts fresh.
        try? FileManager.default.removeItem(at: Self.legacyWorkspaceFileURL)
    }

    func addHomeTab() {
        let tab = WorkspaceTab.home()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func selectTool(_ tool: ToolKind, in tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let nextSequence = (tabs.compactMap { tab -> Int? in
            tab.tool == tool ? tab.sequence : nil
        }.max() ?? 0) + 1

        tabs[index].tool = tool
        tabs[index].sequence = nextSequence
        tabs[index].errorMessage = nil
        selectedTabID = tabID
    }

    func closeTab(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let wasSelected = selectedTabID == tabID
        tabs.remove(at: index)

        if tabs.isEmpty {
            let home = WorkspaceTab.home()
            tabs = [home]
            selectedTabID = home.id
        } else if wasSelected {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeSelectedTab() {
        closeTab(selectedTabID)
    }

    func selectAdjacentTab(offset: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return
        }
        let nextIndex = (index + offset + tabs.count) % tabs.count
        selectedTabID = tabs[nextIndex].id
    }

    private static var legacyWorkspaceFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreDevTools", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }
}
