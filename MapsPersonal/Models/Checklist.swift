import Foundation
import SwiftUI

// MARK: - Checklist Item

struct ChecklistItem: Identifiable {
    let id: UUID
    var text: String
    var isChecked: Bool

    init(text: String, isChecked: Bool = false) {
        self.id = UUID()
        self.text = text
        self.isChecked = isChecked
    }
}

// MARK: - Checklist

struct Checklist: Identifiable {
    let id: UUID
    var name: String
    var items: [ChecklistItem]
    var fileName: String

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.items = []
        // Sanitize name for filename
        let safe = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        self.fileName = "\(safe).md"
    }

    init(fileName: String, name: String, items: [ChecklistItem]) {
        self.id = UUID()
        self.fileName = fileName
        self.name = name
        self.items = items
    }

    var checkedCount: Int {
        items.filter(\.isChecked).count
    }

    var progress: String {
        "\(checkedCount)/\(items.count)"
    }

    // MARK: - Markdown

    func toMarkdown() -> String {
        var lines = ["# \(name)", ""]
        for item in items {
            let check = item.isChecked ? "x" : " "
            lines.append("- [\(check)] \(item.text)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func fromMarkdown(_ content: String, fileName: String) -> Checklist? {
        let lines = content.components(separatedBy: .newlines)
        var name = fileName.replacingOccurrences(of: ".md", with: "")
        var items: [ChecklistItem] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse title: # Name
            if trimmed.hasPrefix("# ") {
                name = String(trimmed.dropFirst(2))
                continue
            }

            // Parse checked: - [x] text
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let text = String(trimmed.dropFirst(6))
                if !text.isEmpty {
                    items.append(ChecklistItem(text: text, isChecked: true))
                }
                continue
            }

            // Parse unchecked: - [ ] text
            if trimmed.hasPrefix("- [ ] ") {
                let text = String(trimmed.dropFirst(6))
                if !text.isEmpty {
                    items.append(ChecklistItem(text: text, isChecked: false))
                }
                continue
            }

            // Plain list item: - text
            if trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                if !text.isEmpty {
                    items.append(ChecklistItem(text: text, isChecked: false))
                }
            }
        }

        return Checklist(fileName: fileName, name: name, items: items)
    }
}

// MARK: - Checklist Store

@Observable
class ChecklistStore {
    var checklists: [Checklist] = []
    private var metadataQuery: NSMetadataQuery?

    private var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jorge.mapspersonal2026")
    }

    private var iCloudDir: URL? {
        guard let container = containerURL else { return nil }
        let dir = container.appendingPathComponent("Documents/Checklists")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var localDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Checklists")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var checklistDir: URL {
        iCloudDir ?? localDir
    }

    init() {
        migrateJsonToMarkdown()
        load()
        startMonitoring()
    }

    func addChecklist(name: String) {
        var checklist = Checklist(name: name)
        // Ensure unique filename
        while checklists.contains(where: { $0.fileName == checklist.fileName }) {
            checklist.fileName = checklist.fileName.replacingOccurrences(of: ".md", with: "-\(Int.random(in: 1...999)).md")
        }
        checklists.append(checklist)
        saveChecklist(checklist)
    }

    func deleteChecklist(at offsets: IndexSet) {
        for index in offsets {
            let file = checklistDir.appendingPathComponent(checklists[index].fileName)
            try? FileManager.default.removeItem(at: file)
        }
        checklists.remove(atOffsets: offsets)
    }

    func addItem(to checklistId: UUID, text: String) {
        guard let index = checklists.firstIndex(where: { $0.id == checklistId }) else { return }
        checklists[index].items.append(ChecklistItem(text: text))
        saveChecklist(checklists[index])
    }

    func toggleItem(checklistId: UUID, itemId: UUID) {
        guard let ci = checklists.firstIndex(where: { $0.id == checklistId }),
              let ii = checklists[ci].items.firstIndex(where: { $0.id == itemId }) else { return }
        checklists[ci].items[ii].isChecked.toggle()
        saveChecklist(checklists[ci])
    }

    func deleteItem(checklistId: UUID, at offsets: IndexSet) {
        guard let ci = checklists.firstIndex(where: { $0.id == checklistId }) else { return }
        checklists[ci].items.remove(atOffsets: offsets)
        saveChecklist(checklists[ci])
    }

    func uncheckAll(checklistId: UUID) {
        guard let ci = checklists.firstIndex(where: { $0.id == checklistId }) else { return }
        for i in checklists[ci].items.indices {
            checklists[ci].items[i].isChecked = false
        }
        saveChecklist(checklists[ci])
    }

    private func saveChecklist(_ checklist: Checklist) {
        let url = checklistDir.appendingPathComponent(checklist.fileName)
        try? checklist.toMarkdown().write(to: url, atomically: true, encoding: .utf8)
    }

    private func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: checklistDir, includingPropertiesForKeys: nil) else { return }

        var loaded: [Checklist] = []
        for file in files where file.pathExtension == "md" {
            guard let content = try? String(contentsOf: file, encoding: .utf8),
                  let checklist = Checklist.fromMarkdown(content, fileName: file.lastPathComponent) else { continue }
            loaded.append(checklist)
        }
        checklists = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func migrateJsonToMarkdown() {
        // Migrate old JSON format to markdown files
        let fm = FileManager.default

        // Check old iCloud JSON
        if let container = containerURL {
            let oldJson = container.appendingPathComponent("Documents/checklists.json")
            migrateJsonFile(at: oldJson)
        }

        // Check old local JSON
        let oldLocal = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("checklists.json")
        migrateJsonFile(at: oldLocal)
    }

    private func migrateJsonFile(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }

        // Decode old format
        struct OldItem: Codable {
            let id: UUID
            let text: String
            let isChecked: Bool
        }
        struct OldChecklist: Codable {
            let id: UUID
            let name: String
            let items: [OldItem]
            let createdAt: Date
        }

        guard let oldLists = try? JSONDecoder().decode([OldChecklist].self, from: data) else { return }

        for old in oldLists {
            let items = old.items.map { ChecklistItem(text: $0.text, isChecked: $0.isChecked) }
            var migrated = Checklist(name: old.name)
            migrated.items = items
            saveChecklist(migrated)
        }

        // Remove old JSON
        try? fm.removeItem(at: url)
    }

    private func startMonitoring() {
        guard iCloudDir != nil else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K ENDSWITH %@", NSMetadataItemFSNameKey, ".md")
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
        query.start()
        metadataQuery = query
    }
}
