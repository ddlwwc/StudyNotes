import Foundation

public struct WebArticleMedia: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceURL: URL
    public let fileName: String
    public let data: Data
    public let mediaType: String

    public init(
        id: String,
        sourceURL: URL,
        fileName: String,
        data: Data,
        mediaType: String
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.data = data
        self.mediaType = mediaType
    }
}

public struct WebArticleMediaFailure: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceURL: URL
    public let message: String

    public init(id: String, sourceURL: URL, message: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.message = message
    }
}

public struct WebArticleDraft: Equatable, Sendable {
    public let sourceURL: URL
    public let rawHTML: String
    public let title: String
    public let markdown: String
    public let media: [WebArticleMedia]
    public let mediaFailures: [WebArticleMediaFailure]

    public init(
        sourceURL: URL,
        rawHTML: String,
        title: String,
        markdown: String,
        media: [WebArticleMedia] = [],
        mediaFailures: [WebArticleMediaFailure] = []
    ) {
        self.sourceURL = sourceURL
        self.rawHTML = rawHTML
        self.title = title
        self.markdown = markdown
        self.media = media
        self.mediaFailures = mediaFailures
    }
}

public struct WebArticleFetcher: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias Progress = @Sendable (String) async -> Void

    private let transport: Transport
    private let maximumImageCount: Int
    private let maximumImageBytes: Int

    public init(
        maximumImageCount: Int = 24,
        maximumImageBytes: Int = 12 * 1024 * 1024,
        transport: @escaping Transport = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.maximumImageCount = maximumImageCount
        self.maximumImageBytes = maximumImageBytes
        self.transport = transport
    }

    public func fetch(
        url: URL,
        progress: Progress? = nil
    ) async throws -> WebArticleDraft {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw StudyNotesContentError.invalidWebArticle
        }
        await progress?("正在读取网页")
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 StudyNotes/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = decodeHTML(data, response: httpResponse),
              !html.isEmpty else {
            throw StudyNotesContentError.invalidWebArticle
        }

        await progress?("正在提取正文")
        let readableHTML = HTMLTextExtractor.extractReadableHTML(html)
        let markdown = HTMLTextExtractor.htmlToMarkdown(readableHTML)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyNotesContentError.invalidWebArticle
        }
        let title = HTMLTextExtractor.title(from: html)
            ?? htmlTitleFallback(from: markdown)
            ?? url.host
            ?? "网页文章"
        let imageURLs = Array(
            HTMLTextExtractor.imageSources(from: readableHTML, baseURL: url)
                .prefix(maximumImageCount)
        )

        var media: [WebArticleMedia] = []
        var failures: [WebArticleMediaFailure] = []
        for (index, imageURL) in imageURLs.enumerated() {
            await progress?("正在保存图片 \(index + 1)/\(imageURLs.count)")
            do {
                var imageRequest = URLRequest(url: imageURL)
                imageRequest.timeoutInterval = 20
                let (imageData, imageResponse) = try await transport(imageRequest)
                guard imageData.count <= maximumImageBytes else {
                    throw WebArticleFetchError.mediaTooLarge
                }
                if let httpResponse = imageResponse as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw WebArticleFetchError.httpStatus(httpResponse.statusCode)
                }
                let fileName = safeMediaFileName(
                    sourceURL: imageURL,
                    response: imageResponse,
                    index: index
                )
                media.append(
                    WebArticleMedia(
                        id: "\(index)-\(ContentFingerprint.sha256(imageData).prefix(12))",
                        sourceURL: imageURL,
                        fileName: fileName,
                        data: imageData,
                        mediaType: mediaType(for: fileName, response: imageResponse)
                    )
                )
            } catch {
                failures.append(
                    WebArticleMediaFailure(
                        id: imageURL.absoluteString,
                        sourceURL: imageURL,
                        message: error.localizedDescription
                    )
                )
            }
        }
        await progress?("正文与 \(media.count) 张图片已准备")
        return WebArticleDraft(
            sourceURL: url,
            rawHTML: html,
            title: title,
            markdown: markdown,
            media: media,
            mediaFailures: failures
        )
    }

    private func decodeHTML(_ data: Data, response: URLResponse) -> String? {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        let encodingName = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .components(separatedBy: "charset=")
            .last?
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let encodingName,
           let encoding = String.Encoding(
               iconvName: encodingName
           ) {
            return String(data: data, encoding: encoding)
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private func htmlTitleFallback(from markdown: String) -> String? {
        markdown
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    }

    private func safeMediaFileName(
        sourceURL: URL,
        response: URLResponse,
        index: Int
    ) -> String {
        let rawExtension = sourceURL.pathExtension.lowercased()
        let allowed = ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif"]
        let fileExtension = allowed.contains(rawExtension)
            ? rawExtension
            : mediaType(for: "", response: response) == "image/png" ? "png" : "jpg"
        return String(format: "image-%02d.%@", index + 1, fileExtension)
    }

    private func mediaType(for fileName: String, response: URLResponse) -> String {
        if let contentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .components(separatedBy: ";")
            .first,
           contentType.hasPrefix("image/") {
            return contentType
        }
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }
}

private enum WebArticleFetchError: LocalizedError {
    case mediaTooLarge
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .mediaTooLarge:
            "图片超过本地保存上限。"
        case .httpStatus(let code):
            "图片请求返回 HTTP \(code)。"
        }
    }
}

private extension String.Encoding {
    init?(iconvName: String) {
        switch iconvName.lowercased() {
        case "utf-8", "utf8":
            self = .utf8
        case "gb18030", "gbk", "gb2312":
            self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            ))
        case "big5":
            self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            ))
        case "iso-8859-1", "latin1":
            self = .isoLatin1
        default:
            return nil
        }
    }
}
