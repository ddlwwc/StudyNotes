import CoreTransferable
import Foundation
import StudyNotesKit
import UniformTypeIdentifiers

public enum WorkspaceSettingsPage: String, CaseIterable, Identifiable, Sendable {
    case workspace
    case ai
    case publishing
    case credentials
    case reading

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .workspace:
            "学习目录"
        case .ai:
            "AI 配置"
        case .publishing:
            "发布配置"
        case .credentials:
            "密钥与凭据"
        case .reading:
            "阅读偏好"
        }
    }

    public var systemImage: String {
        switch self {
        case .workspace:
            "folder"
        case .ai:
            "sparkles"
        case .publishing:
            "paperplane"
        case .credentials:
            "key"
        case .reading:
            "textformat.size"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var publishingServerURL: String
    public var defaultPublishVisibility: PublishVisibility
    public var publishAnnotationsByDefault: Bool
    public var publishAIByDefault: Bool
    public var defaultAIProviderID: UUID?

    public init(
        publishingServerURL: String = "http://127.0.0.1:8090",
        defaultPublishVisibility: PublishVisibility = .unlisted,
        publishAnnotationsByDefault: Bool = false,
        publishAIByDefault: Bool = false,
        defaultAIProviderID: UUID? = nil
    ) {
        self.publishingServerURL = publishingServerURL
        self.defaultPublishVisibility = defaultPublishVisibility
        self.publishAnnotationsByDefault = publishAnnotationsByDefault
        self.publishAIByDefault = publishAIByDefault
        self.defaultAIProviderID = defaultAIProviderID
    }
}

@MainActor
public final class AppSettingsStore {
    private static let key = "StudyNotes.AppSettings.v1"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> AppSettings {
        guard let data = userDefaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            var settings = AppSettings()
            if let legacyServerURL = userDefaults.string(
                forKey: "StudyNotes.Publishing.ServerURL"
            ) {
                settings.publishingServerURL = legacyServerURL
            }
            return settings
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        userDefaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }

    public func update(_ change: (inout AppSettings) -> Void) throws {
        var settings = load()
        change(&settings)
        try save(settings)
    }
}

public enum ServiceConnectionStatus: Equatable, Sendable {
    case idle
    case testing
    case succeeded(String)
    case failed(String)
}

public struct ServiceConnectionResult: Equatable, Sendable {
    public let status: ServiceConnectionStatus
    public let usesHTTP: Bool

    public init(status: ServiceConnectionStatus, usesHTTP: Bool) {
        self.status = status
        self.usesHTTP = usesHTTP
    }
}

public enum StudyNotesServiceEndpoint: String, Sendable {
    case publishing
    case media

    public var title: String {
        switch self {
        case .publishing:
            "发布服务"
        case .media:
            "媒体服务"
        }
    }
}

public struct ServiceConnectionTester: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    public init(
        transport: @escaping Transport = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.transport = transport
    }

    public func test(
        _ endpoint: StudyNotesServiceEndpoint,
        serverURLText: String,
        bearerToken: String? = nil
    ) async -> ServiceConnectionResult {
        let trimmedURL = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedURL),
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil else {
            return ServiceConnectionResult(
                status: .failed("服务器地址必须是完整的 HTTP(S) 地址。"),
                usesHTTP: false
            )
        }

        let usesHTTP = scheme == "http"
        var request = URLRequest(
            url: baseURL
                .appending(path: "api")
                .appending(path: "v1")
                .appending(path: "health")
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint == .media,
           let bearerToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else {
                return ServiceConnectionResult(
                    status: .failed("服务返回了无法识别的响应。"),
                    usesHTTP: usesHTTP
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                return ServiceConnectionResult(
                    status: .failed("HTTP \(response.statusCode)"),
                    usesHTTP: usesHTTP
                )
            }
            if let health = try? JSONDecoder().decode(HealthPayload.self, from: data),
               health.ok == false {
                return ServiceConnectionResult(
                    status: .failed(health.message ?? "服务报告自身不可用。"),
                    usesHTTP: usesHTTP
                )
            }
            return ServiceConnectionResult(
                status: .succeeded(
                    endpoint == .media && !(bearerToken?.isEmpty ?? true)
                        ? "服务可达，Bearer 凭据已随请求发送。"
                        : "服务可达。"
                ),
                usesHTTP: usesHTTP
            )
        } catch {
            return ServiceConnectionResult(
                status: .failed(error.localizedDescription),
                usesHTTP: usesHTTP
            )
        }
    }
}

private struct HealthPayload: Decodable {
    let ok: Bool
    let message: String?
}

public struct WorkspaceDragPayload: Codable, Equatable, Sendable, Transferable {
    public enum Kind: String, Codable, Sendable {
        case folder
        case materials
    }

    public let kind: Kind
    public let knowledgeBaseID: UUID?
    public let folderPath: String?
    public let materialIDs: [UUID]

    public init(
        kind: Kind,
        knowledgeBaseID: UUID?,
        folderPath: String? = nil,
        materialIDs: [UUID] = []
    ) {
        self.kind = kind
        self.knowledgeBaseID = knowledgeBaseID
        self.folderPath = folderPath
        self.materialIDs = materialIDs
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

public enum WorkspaceDropTarget: Equatable, Sendable {
    case knowledgeBaseRoot(UUID)
    case folder(knowledgeBaseID: UUID, path: String)

    public var knowledgeBaseID: UUID {
        switch self {
        case let .knowledgeBaseRoot(id):
            id
        case let .folder(id, _):
            id
        }
    }

    public var folderPath: String {
        switch self {
        case .knowledgeBaseRoot:
            ""
        case let .folder(_, path):
            path
        }
    }
}

public enum WorkspaceDropRules {
    public static func allows(
        _ payload: WorkspaceDragPayload,
        on target: WorkspaceDropTarget
    ) -> Bool {
        switch payload.kind {
        case .materials:
            return !payload.materialIDs.isEmpty
        case .folder:
            guard let sourcePath = payload.folderPath,
                  !sourcePath.isEmpty,
                  payload.knowledgeBaseID == target.knowledgeBaseID else {
                return false
            }
            let targetPath = target.folderPath
            return targetPath != sourcePath
                && !targetPath.hasPrefix("\(sourcePath)/")
        }
    }
}
