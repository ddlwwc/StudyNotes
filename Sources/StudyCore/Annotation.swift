import Foundation

public struct Comment: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var author: String
    public var text: String
    public var createdAt: Date
    public var replies: [Comment]

    public init(
        id: String = UUID().uuidString,
        author: String = "我",
        text: String,
        createdAt: Date = Date(),
        replies: [Comment] = []
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = Self.normalized(createdAt)
        self.replies = replies
    }

    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    public var totalCount: Int {
        1 + replies.reduce(0) { $0 + $1.totalCount }
    }

    public func addingReply(_ reply: Comment, to targetID: String) -> Comment? {
        if id == targetID {
            var updated = self
            updated.replies.append(reply)
            return updated
        }
        for (index, child) in replies.enumerated() {
            if let replaced = child.addingReply(reply, to: targetID) {
                var updated = self
                updated.replies[index] = replaced
                return updated
            }
        }
        return nil
    }

    public func removingReply(_ targetID: String) -> Comment? {
        let filtered = replies.filter { $0.id != targetID }
        if filtered.count != replies.count {
            var updated = self
            updated.replies = filtered
            return updated
        }
        for (index, child) in replies.enumerated() {
            if let replaced = child.removingReply(targetID) {
                var updated = self
                updated.replies[index] = replaced
                return updated
            }
        }
        return nil
    }
}

public struct Annotation: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var anchorText: String
    public var comments: [Comment]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        anchorText: String,
        comments: [Comment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.anchorText = anchorText
        self.comments = comments
        self.createdAt = Comment.normalized(createdAt)
    }

    public var commentCount: Int {
        comments.reduce(0) { $0 + $1.totalCount }
    }
}

public struct AnnotationFile: Equatable, Sendable, Codable {
    public var version: Int
    public var annotations: [Annotation]

    public init(version: Int = 1, annotations: [Annotation] = []) {
        self.version = version
        self.annotations = annotations
    }

    public func annotation(id: String) -> Annotation? {
        annotations.first { $0.id == id }
    }

    public mutating func upsert(_ annotation: Annotation) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        } else {
            annotations.append(annotation)
        }
    }

    public mutating func remove(id: String) {
        annotations.removeAll { $0.id == id }
    }
}
