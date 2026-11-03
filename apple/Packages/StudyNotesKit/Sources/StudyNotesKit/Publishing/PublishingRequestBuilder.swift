import Foundation

public enum PublishingRequestBuilder {
    public static func make(
        preview: PublishPreview,
        tags: [String],
        visibility: PublishingVisibility,
        expectedVersion: Int,
        articleID: String?,
        uploadedMedia: [UploadedPublishingMedia],
        requestID: String = PublishingIdentifiers.requestID()
    ) throws -> PublishingRequest {
        guard visibility != .withdrawn else {
            throw PublishingClientError.invalidResponse
        }
        let bodyHTML = try publicationBody(
            from: preview,
            uploadedMedia: uploadedMedia
        )
        let annotations: [PublishingAnnotation]? = preview.includeAnnotations
            ? try preview.annotations.map { annotation in
                let note = annotation.note.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !note.isEmpty else {
                    throw PublishingClientError.emptyAnnotationNote(
                        annotation.id.uuidString
                    )
                }
                return PublishingAnnotation(
                    id: annotation.id.uuidString,
                    quote: annotation.quote,
                    note: note,
                    blockId: annotation.anchor.blockPath.isEmpty
                        ? nil
                        : annotation.anchor.blockPath
                            .map(String.init)
                            .joined(separator: ".")
                )
            }
            : nil
        let aiAppendix: [PublishingAIAppendixItem]? = {
            guard preview.includeAI,
                  let body = preview.aiAppendix?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !body.isEmpty else {
                return nil
            }
            return [
                PublishingAIAppendixItem(
                    id: "ai-appendix",
                    title: "AI 研读附录",
                    body: body
                )
            ]
        }()
        let normalizedTags = Array(
            Set(
                tags.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
        ).sorted()
        let articleID = articleID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PublishingRequest(
            requestId: requestID,
            articleId: articleID?.isEmpty == false ? articleID : nil,
            sourceMaterialId: preview.materialID.uuidString,
            expectedVersion: max(0, expectedVersion),
            visibility: visibility,
            title: preview.title.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyHtml: bodyHTML,
            tags: normalizedTags,
            publishAnnotations: preview.includeAnnotations,
            publishAi: preview.includeAI,
            annotations: preview.includeAnnotations ? annotations : nil,
            aiAppendix: preview.includeAI ? aiAppendix : nil,
            mediaRefs: uploadedMedia.isEmpty
                ? nil
                : uploadedMedia.map(\.reference)
                    .sorted { $0.objectKey < $1.objectKey }
        )
    }

    public static func publicationBody(
        from preview: PublishPreview,
        uploadedMedia: [UploadedPublishingMedia]
    ) throws -> String {
        guard var body = firstCapture(
            pattern: #"(?is)<article\b[^>]*>(.*?)</article>"#,
            in: preview.html
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !body.isEmpty else {
            throw PublishingClientError.invalidBodyHTML
        }
        body = replacingFirst(
            pattern: #"(?is)^\s*<h1\b[^>]*>.*?</h1>"#,
            in: body,
            with: ""
        )
        body = replacing(
            pattern: #"(?is)<section\b[^>]*class="[^"]*published-annotations[^"]*"[^>]*>.*?</section>"#,
            in: body,
            with: ""
        )
        body = replacing(
            pattern: #"(?is)<details\b[^>]*class="[^"]*study-appendix[^"]*"[^>]*>.*?</details>"#,
            in: body,
            with: ""
        )
        body = replacing(
            pattern: #"(?is)<script\b[^>]*>.*?</script>"#,
            in: body,
            with: ""
        )

        for uploaded in uploadedMedia {
            guard let media = preview.media.first(where: {
                $0.id == uploaded.itemID
            }) else {
                continue
            }
            body = body.replacingOccurrences(
                of: #"data-media-key="\#(media.fileName)""#,
                with: #"data-object-key="\#(uploaded.reference.objectKey)""#
            )
        }
        if let missing = firstCapture(
            pattern: #"(?is)data-media-key="([^"]+)""#,
            in: body
        ), !missing.isEmpty {
            throw PublishingClientError.missingMediaReference(missing)
        }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublishingClientError.invalidBodyHTML
        }
        return body
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }

    private static func replacingFirst(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..., in: value)
              ) else {
            return value
        }
        guard let range = Range(match.range, in: value) else {
            return value
        }
        var result = value
        result.replaceSubrange(range, with: replacement)
        return result
    }

    private static func firstCapture(
        pattern: String,
        in value: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }
}
