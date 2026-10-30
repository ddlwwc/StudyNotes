import Foundation
import StudyCore
import Observation

@MainActor
@Observable
public final class AnnotationStore {
    public private(set) var file = AnnotationFile()
    public private(set) var lastError: String?
    public private(set) var resolved: [(annotation: Annotation, range: NSRange)] = []

    private var directory: URL?
    private var currentName: String?

    public init() {}

    public func attach(directory: URL?) {
        self.directory = directory
    }

    public var url: URL? {
        guard let directory, let currentName else { return nil }
        return directory.appendingPathComponent(currentName)
    }

    public func load(note: Note) {
        currentName = Self.fileName(for: note)
        file = AnnotationFile()
        lastError = nil
        guard let url else { return }
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            file = try JSONDecoder.study.decode(AnnotationFile.self, from: data)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refresh(with source: String) {
        resolved = AnnotationAnchor.resolve(file, in: source)
    }

    public func add(annotation: Annotation, source: String) {
        file.upsert(annotation)
        resolveAndPersist(source: source)
    }

    public func addComment(_ text: String, to annotationID: String, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let existing = file.annotation(id: annotationID) else { return }
        var updated = existing
        updated.comments.append(Comment(text: trimmed))
        file.upsert(updated)
        resolveAndPersist(source: source)
    }

    public func addReply(_ text: String, to commentID: String, annotationID: String, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let existing = file.annotation(id: annotationID) else { return }

        var updatedComments: [Comment] = []
        var matched = false
        for comment in existing.comments {
            if let replaced = comment.addingReply(Comment(text: trimmed), to: commentID) {
                updatedComments.append(replaced)
                matched = true
            } else {
                updatedComments.append(comment)
            }
        }
        guard matched else { return }

        var updated = existing
        updated.comments = updatedComments
        file.upsert(updated)
        resolveAndPersist(source: source)
    }

    public func remove(annotationID: String, source: String) {
        file.remove(id: annotationID)
        resolveAndPersist(source: source)
    }

    public func annotations(at sourceRange: NSRange) -> [Annotation] {
        resolved
            .filter { NSIntersectionRange($0.range, sourceRange).length > 0 }
            .map(\.annotation)
    }

    public func annotation(for anchorText: String) -> Annotation? {
        file.annotations.last { $0.anchorText == anchorText }
    }

    private func resolveAndPersist(source: String) {
        resolved = AnnotationAnchor.resolve(file, in: source)
        persist()
    }

    private func persist() {
        guard let url else { return }
        do {
            let data = try JSONEncoder.study.encode(file)
            try FileIO.write(String(decoding: data, as: UTF8.self), to: url)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func fileName(for note: Note) -> String {
        let base = (note.id as NSString).lastPathComponent
        let stem = base.hasSuffix(".md") ? String(base.dropLast(3)) : base
        return "\(stem).json"
    }
}
