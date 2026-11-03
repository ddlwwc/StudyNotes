import Foundation

public enum MarkdownEditorResources {
    public static let messageHandlerName = "markdownEditor"

    public static var webResource: MarkdownEditorWebResource {
        guard let htmlURL = Bundle.module.url(
            forResource: "editor",
            withExtension: "html"
        ) else {
            preconditionFailure("StudyNotes editor resource is missing")
        }
        return MarkdownEditorWebResource(
            htmlURL: htmlURL,
            baseURL: htmlURL.deletingLastPathComponent(),
            messageHandlerName: messageHandlerName
        )
    }
}
