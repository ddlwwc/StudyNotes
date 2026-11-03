import UIKit
import UniformTypeIdentifiers
import StudyNotesIOSCore

final class ShareViewController: UIViewController {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var payload: SharePayload?
    private var isCollecting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task {
            await loadAndCollect()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        iconView.image = UIImage(systemName: "tray.and.arrow.down.fill")
        iconView.tintColor = UIColor(red: 0.2, green: 0.44, blue: 1, alpha: 1)
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = "正在写入收件箱"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        detailLabel.text = "内容会保留在共享收件箱，等待 Mac 统一整理。"
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        progressView.startAnimating()

        retryButton.setTitle("重试", for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        retryButton.isHidden = true

        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 13)
        closeButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let actionStack = UIStackView(arrangedSubviews: [retryButton, closeButton])
        actionStack.axis = .horizontal
        actionStack.spacing = 20
        actionStack.alignment = .center

        let stack = UIStackView(
            arrangedSubviews: [
                iconView,
                titleLabel,
                detailLabel,
                progressView,
                actionStack
            ]
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func loadAndCollect() async {
        guard !isCollecting else {
            return
        }
        isCollecting = true
        defer { isCollecting = false }
        setLoading(true)

        do {
            let payload = try await SharePayloadLoader.load(
                from: extensionContext?.inputItems ?? []
            )
            self.payload = payload
            try await collect(payload)
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    private func collect(_ payload: SharePayload) async throws {
        let rootState = StudyNotesFileSupport.resolveRoot(allowLocalFallback: true)
        guard let rootURL = rootState.url else {
            throw ShareError.iCloudUnavailable(rootState.label)
        }
        let inbox = try InboxStore(rootURL: rootURL)
        let item = try await inbox.collect(
            InboxDraft(
                kind: payload.kind,
                title: payload.title,
                payloadFileExtension: payload.fileExtension,
                payloadData: payload.data,
                source: "iOS 分享"
            )
        )
        switch item.status {
        case .collected:
            showSuccess()
        case .pending, .failed:
            throw ShareError.writeFailed
        }
    }

    @objc private func retry() {
        guard let payload else {
            return
        }
        Task {
            setLoading(true)
            do {
                try await collect(payload)
            } catch {
                showFailure(error.localizedDescription)
            }
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "StudyNotesShare",
                code: NSUserCancelledError
            )
        )
    }

    private func setLoading(_ loading: Bool) {
        progressView.isHidden = !loading
        retryButton.isHidden = true
        closeButton.isHidden = loading
        titleLabel.text = loading ? "正在写入收件箱" : titleLabel.text
        detailLabel.text = "内容会保留在共享收件箱，等待 Mac 统一整理。"
    }

    private func showSuccess() {
        progressView.stopAnimating()
        progressView.isHidden = true
        retryButton.isHidden = true
        closeButton.isHidden = true
        iconView.image = UIImage(systemName: "checkmark.circle.fill")
        iconView.tintColor = .systemGreen
        titleLabel.text = "已写入收件箱"
        detailLabel.text = "Mac 连接同一 iCloud 容器后可继续整理。"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.extensionContext?.completeRequest(
                returningItems: nil,
                completionHandler: nil
            )
        }
    }

    private func showFailure(_ message: String) {
        progressView.stopAnimating()
        progressView.isHidden = true
        retryButton.isHidden = payload == nil
        closeButton.isHidden = false
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = .systemOrange
        titleLabel.text = "收件箱写入失败"
        detailLabel.text = payload == nil
            ? message
            : "本地草稿已保留，可重试。\n\(message)"
    }
}

private struct SharePayload {
    let kind: InboxItemKind
    let title: String
    let fileExtension: String
    let data: Data
}

private enum ShareError: LocalizedError {
    case noSupportedContent
    case unreadableContent
    case iCloudUnavailable(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noSupportedContent:
            "没有找到可收集的网址、图片或文本。"
        case .unreadableContent:
            "无法读取分享内容。"
        case let .iCloudUnavailable(reason):
            reason
        case .writeFailed:
            "收件箱写入未完成。"
        }
    }
}

@MainActor
private enum SharePayloadLoader {
    static func load(from inputItems: [Any]) async throws -> SharePayload {
        let providers = inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try await loadURL(from: provider) {
                    return SharePayload(
                        kind: .url,
                        title: url.host ?? url.absoluteString,
                        fileExtension: "txt",
                        data: Data(url.absoluteString.utf8)
                    )
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                if let image = try await loadImage(from: provider) {
                    return image
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try await loadText(from: provider) {
                    let title = String(
                        text
                            .split(separator: "\n")
                            .first?
                            .prefix(60) ?? "文本片段"
                    )
                    return SharePayload(
                        kind: .text,
                        title: title,
                        fileExtension: "txt",
                        data: Data(text.utf8)
                    )
                }
            }
        }
        throw ShareError.noSupportedContent
    }

    private static func loadURL(from provider: NSItemProvider) async throws -> URL? {
        let item = try await loadItem(
            typeIdentifier: UTType.url.identifier,
            from: provider
        )
        if let url = item.value as? URL {
            return url
        }
        if let url = item.value as? NSURL {
            return url as URL
        }
        if let data = item.value as? Data,
           let value = String(data: data, encoding: .utf8),
           let url = URL(string: value) {
            return url
        }
        return nil
    }

    private static func loadText(from provider: NSItemProvider) async throws -> String? {
        if let value = try await provider.loadItem(
            forTypeIdentifier: UTType.plainText.identifier
        ) as? String {
            return value
        }
        if let value = try await provider.loadItem(
            forTypeIdentifier: UTType.plainText.identifier
        ) as? NSString {
            return value as String
        }
        if let data = try await provider.loadItem(
            forTypeIdentifier: UTType.plainText.identifier
        ) as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private static func loadImage(from provider: NSItemProvider) async throws -> SharePayload? {
        let item = try await loadItem(
            typeIdentifier: UTType.image.identifier,
            from: provider
        )
        if let data = item.value as? Data {
            return SharePayload(
                kind: .image,
                title: "分享图片",
                fileExtension: "png",
                data: data
            )
        }
        if let image = item.value as? UIImage,
           let data = image.pngData() {
            return SharePayload(
                kind: .image,
                title: "分享图片",
                fileExtension: "png",
                data: data
            )
        }
        return nil
    }

    private static func loadItem(
        typeIdentifier: String,
        from provider: NSItemProvider
    ) async throws -> LoadedProviderItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: typeIdentifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: LoadedProviderItem(value: item))
                }
            }
        }
    }
}

private struct LoadedProviderItem: @unchecked Sendable {
    let value: NSSecureCoding?
}
