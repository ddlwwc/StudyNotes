import Foundation
import StudyCore
import Observation

@MainActor
@Observable
public final class NoteStore {
    public private(set) var notes: [Note] = []
    public private(set) var lastError: String?

    private var vault: Vault?

    public init() {}

    public var allCards: [Card] {
        notes.flatMap(\.cards)
    }

    public func attach(_ vault: Vault) {
        self.vault = vault
        reload()
    }

    public func detach() {
        vault = nil
        notes = []
        lastError = nil
    }

    public func reload() {
        guard let vault else { return }
        do {
            let urls = try FileIO.listMarkdownFiles(in: vault.notesURL)
            var loaded: [Note] = []
            for url in urls {
                let content = try FileIO.read(url)
                let relative = VaultLayout.notesDirectory + "/" + url.lastPathComponent
                loaded.append(MarkdownCardParser.parseNote(relativePath: relative, content: content))
            }
            notes = loaded
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func url(for note: Note) -> URL? {
        guard let vault else { return nil }
        let name = (note.id as NSString).lastPathComponent
        return vault.notesURL.appendingPathComponent(name)
    }

    public func body(of note: Note) -> String {
        guard let url = url(for: note) else { return "" }
        return (try? FileIO.read(url)) ?? ""
    }

    public func save(note: Note, content: String) throws {
        guard let url = url(for: note) else { throw VaultError.noVaultSelected }
        try FileIO.write(content, to: url)
        reload()
    }

    public func create(title: String, tags: [String]) throws -> Note {
        guard let vault else { throw VaultError.noVaultSelected }
        let slug = title.isEmpty ? "未命名" : title
        let candidate = FileIO.availableNoteName(in: vault.notesURL, base: slug)
        let tagLine = tags.isEmpty ? "" : "\ntags: [\(tags.joined(separator: ", "))]"
        let content = "---\(tagLine)\n---\n# \(slug)\n\n"
        try FileIO.write(content, to: candidate)
        reload()
        let relative = VaultLayout.notesDirectory + "/" + candidate.lastPathComponent
        return notes.first { $0.id == relative }
            ?? Note(id: relative, title: slug, tags: tags)
    }

    public struct ImportOutcome: Sendable {
        public var imported: [String]
        public var skipped: [String]
        public var failed: [(name: String, reason: String)]

        public var summary: String {
            var parts: [String] = []
            if !imported.isEmpty { parts.append("导入 \(imported.count) 篇") }
            if !skipped.isEmpty { parts.append("跳过同名 \(skipped.count) 篇") }
            if !failed.isEmpty { parts.append("失败 \(failed.count) 篇") }
            return parts.isEmpty ? "没有可导入的文件" : parts.joined(separator: "，")
        }
    }

    public func importNotes(urls: [URL]) -> ImportOutcome {
        var imported: [String] = []
        var skipped: [String] = []
        var failed: [(String, String)] = []

        guard let vault else {
            return ImportOutcome(
                imported: [],
                skipped: [],
                failed: urls.map { ($0.lastPathComponent, "还没有选择笔记目录") }
            )
        }

        var existing = Set<String>()
        if let names = try? FileIO.listMarkdownFiles(in: vault.notesURL) {
            existing = Set(names.map(\.lastPathComponent))
        }

        let scoped = urls.map { url -> URL in
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        for url in scoped {
            do {
                let content = try FileIO.read(url)
                switch NoteImport.decide(
                    sourceName: url.lastPathComponent,
                    content: content,
                    existingNames: existing
                ) {
                case let .skip(reason):
                    skipped.append("\(url.lastPathComponent)（\(reason)）")
                case let .write(targetName):
                    let target = vault.notesURL.appendingPathComponent(targetName)
                    try FileIO.write(content, to: target)
                    existing.insert(targetName)
                    imported.append(targetName)
                }
            } catch {
                failed.append((url.lastPathComponent, error.localizedDescription))
            }
        }

        reload()
        return ImportOutcome(imported: imported, skipped: skipped, failed: failed)
    }

    public func delete(note: Note) throws {
        guard let url = url(for: note) else { throw VaultError.noVaultSelected }
        try FileManager.default.removeItem(at: url)
        reload()
    }
}
