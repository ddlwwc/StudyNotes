import StudyNotesKit
import SwiftUI

public enum SnapshotWorkspaceMode: Equatable {
    case tree
    case searchResults
    case readerOutline
    case settings
    case compactSettings
    case aiSettings
    case compactAISettings
    case emptyAISettings
    case compactEmptyAISettings

    var isShowingSettings: Bool {
        self == .settings
            || self == .compactSettings
            || isShowingAISettings
    }

    var isShowingAISettings: Bool {
        self == .aiSettings
            || self == .compactAISettings
            || self == .emptyAISettings
            || self == .compactEmptyAISettings
    }

    var isShowingEmptyAISettings: Bool {
        self == .emptyAISettings || self == .compactEmptyAISettings
    }

    public var canvasSize: CGSize {
        switch self {
        case .compactSettings, .compactAISettings, .compactEmptyAISettings:
            CGSize(
                width: SNMetric.minimumWindowWidth,
                height: SNMetric.minimumWindowHeight
            )
        case .tree, .searchResults, .readerOutline, .settings,
             .aiSettings, .emptyAISettings:
            CGSize(width: 1_440, height: 1_024)
        }
    }
}

@MainActor
public struct SnapshotWorkspaceView: View {
    private let mode: SnapshotWorkspaceMode
    private let isDarkMode: Bool
    @State private var model: WorkspaceModel

    public init(
        mode: SnapshotWorkspaceMode = .tree,
        isDarkMode: Bool = false
    ) {
        self.mode = mode
        self.isDarkMode = isDarkMode
        _model = State(
            initialValue: SnapshotWorkspaceFixture.makeModel(mode: mode)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            WorkspaceSnapshotHeader(
                showsWorkspaceActions: !mode.isShowingSettings
            )
            HStack(spacing: 0) {
                SnapshotSidebar(isShowingSettings: mode.isShowingSettings)
                    .frame(width: SNMetric.sidebarWidth)

                if mode.isShowingSettings {
                    SettingsView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if mode == .readerOutline {
                        SnapshotOutline()
                            .frame(width: 240)
                    } else {
                        SnapshotMaterialList(mode: mode)
                            .frame(width: SNMetric.materialListWidth)
                    }

                    SnapshotReader()
                        .frame(minWidth: 460, maxWidth: .infinity)

                    SnapshotStudyPanel()
                        .frame(width: SNMetric.studyPanelWidth)
                }
            }
        }
        .frame(width: mode.canvasSize.width, height: mode.canvasSize.height)
        .background(SNColor.white)
        .environment(\.colorScheme, isDarkMode ? .dark : .light)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

#Preview("知识库工作台") {
    SnapshotWorkspaceView()
}

@MainActor
private enum SnapshotWorkspaceFixture {
    private static let alphaID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000059"
    )!
    private static let betaID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000060"
    )!

    static func makeModel(mode: SnapshotWorkspaceMode) -> WorkspaceModel {
        let suiteName = "StudyNotesMacSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettingsStore = AppSettingsStore(userDefaults: defaults)
        let secretStore = SnapshotMemorySecretStore()

        if mode.isShowingAISettings {
            configureAIProfiles(
                defaults: defaults,
                appSettingsStore: appSettingsStore,
                secretStore: secretStore,
                includesProfiles: !mode.isShowingEmptyAISettings
            )
        }

        let model = WorkspaceModel(
            rootStore: WorkspaceRootStore(userDefaults: defaults),
            secretStore: secretStore,
            mediaSecretStore: SnapshotMemorySecretStore(),
            devicePreferences: DevicePreferencesStore(userDefaults: defaults),
            appSettingsStore: appSettingsStore,
            providerUserDefaults: defaults,
            treeExpansionStore: WorkspaceTreeExpansionStore(
                userDefaults: defaults
            )
        )
        if mode.isShowingAISettings {
            model.settingsPage = .ai
        }
        return model
    }

    private static func configureAIProfiles(
        defaults: UserDefaults,
        appSettingsStore: AppSettingsStore,
        secretStore: SnapshotMemorySecretStore,
        includesProfiles: Bool
    ) {
        guard includesProfiles else {
            try? appSettingsStore.save(AppSettings())
            return
        }

        let alpha = AIProviderProfile(
            id: alphaID,
            name: "Alpha Cloud",
            baseURL: URL(string: "https://api.alpha.example/v1")!,
            model: "alpha-chat",
            keychainAccount: "snapshot.alpha"
        )
        let beta = AIProviderProfile(
            id: betaID,
            name: "Beta Local",
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            model: "beta-chat",
            keychainAccount: "snapshot.beta"
        )

        AIProviderSettingsStore(userDefaults: defaults).save([beta, alpha])
        try? appSettingsStore.save(AppSettings(defaultAIProviderID: alpha.id))
        try? secretStore.save(
            "snapshot-placeholder-key",
            account: alpha.keychainAccount
        )
    }
}

private final class SnapshotMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ secret: String, account: String) throws {
        lock.withLock {
            values[account] = secret
        }
    }

    func load(account: String) throws -> String? {
        lock.withLock {
            values[account]
        }
    }

    func delete(account: String) throws {
        lock.withLock {
            _ = values.removeValue(forKey: account)
        }
    }
}

private struct SnapshotSidebar: View {
    var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("知识库")
                    .font(.sn(18, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SNColor.text)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("开始")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.muted)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                SnapshotSidebarRow(
                    title: "全部材料",
                    systemImage: "tray.full",
                    count: "6"
                )
                SnapshotSidebarRow(
                    title: "收件箱",
                    systemImage: "tray",
                    count: "2"
                )
                SnapshotSidebarRow(
                    title: "回收站",
                    systemImage: "trash",
                    count: "1"
                )

                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                HStack {
                    Text("我的知识库")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                    Spacer()
                    Text("1")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                SnapshotSidebarRow(
                    title: "学习科学",
                    systemImage: "books.vertical",
                    count: "6",
                    isSelected: !isShowingSettings
                )

                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                HStack {
                    Text("标签")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                    Spacer()
                    Text("2")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                SnapshotSidebarRow(
                    title: "认知负荷",
                    systemImage: "tag",
                    count: "2"
                )
                SnapshotSidebarRow(
                    title: "教学设计",
                    systemImage: "tag",
                    count: "1"
                )
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                SnapshotSidebarRow(
                    title: "设置",
                    systemImage: "gearshape",
                    isSelected: isShowingSettings
                )
                .padding(.horizontal, -9)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(SNColor.green)
                            .frame(width: 6, height: 6)
                        Text("iCloud 目录 · 已连接")
                            .font(.sn(10, weight: .medium))
                            .foregroundStyle(SNColor.text)
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(SNColor.muted)
                    }
                    Text("StudyNotes")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background(SNColor.nav)
    }
}

private struct SnapshotSidebarRow: View {
    let title: String
    let systemImage: String
    var count: String?
    var detail: String?
    var isSelected = false
    var indentation = 0

    var body: some View {
        HStack(spacing: 9) {
            Color.clear
                .frame(width: CGFloat(max(0, indentation - 1)) * 13)

            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                .frame(width: 16)
            Text(title)
                .font(.sn(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                .lineLimit(1)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            } else if let count {
                Text(count)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
    }
}

private struct SnapshotMaterialList: View {
    let mode: SnapshotWorkspaceMode

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("基础")
                        .font(.sn(15, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                    Spacer()
                }
                Text("学习科学 / 基础 · 3 篇材料")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(SNColor.muted)
                Text(
                    mode == .tree
                        ? "搜索当前材料"
                        : "工作记忆"
                )
                    .font(.sn(11))
                    .foregroundStyle(
                        mode == .tree ? SNColor.muted : SNColor.text
                    )
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(SNColor.nav)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
            .padding(.horizontal, 12)

            if mode == .tree {
                treeContent
            } else {
                searchContent
            }

            Spacer()
        }
        .background(SNColor.white)
    }

    private var treeContent: some View {
        VStack(spacing: 0) {
            SnapshotTreeSummary(
                count: "全部 5",
                detail: "文件夹优先 · 按名称"
            )
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
            SnapshotRootRow(count: "5")
            SnapshotFolderRow(
                title: "基础",
                count: "3",
                expanded: true,
                isSelected: true
            )
            SnapshotTreeMaterialRow(
                title: "认知负荷理论与学习设计",
                depth: 1,
                isSelected: true
            )
            SnapshotFolderRow(
                title: "图论",
                count: "2",
                depth: 1,
                expanded: true
            )
            SnapshotTreeMaterialRow(
                title: "多媒体学习的双通道假设",
                depth: 2
            )
            SnapshotFolderRow(
                title: "归档",
                count: "0"
            )
            SnapshotTreeMaterialRow(
                title: "工作记忆模型",
                depth: 0
            )
        }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            SnapshotTreeSummary(
                count: "2 个结果",
                detail: "扁平搜索结果"
            )
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
            SnapshotSearchResultRow(
                title: "工作记忆模型",
                path: "学习科学 / 基础",
                isSelected: true
            )
            SnapshotSearchResultRow(
                title: "认知负荷理论与学习设计",
                path: "学习科学 / 基础 / 图论"
            )
        }
    }
}

private struct SnapshotTreeSummary: View {
    let count: String
    let detail: String

    var body: some View {
        HStack {
            Text(count)
                .font(.sn(11, weight: .medium))
                .foregroundStyle(SNColor.blue)
            Spacer()
            Text(detail)
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }
}

private struct SnapshotSearchResultRow: View {
    let title: String
    let path: String
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(SNColor.blue)
                .frame(width: 22, height: 22)
                .background(SNColor.blueSoft)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(1)
                Text(path)
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
                .padding(.leading, 42)
        }
    }
}

private struct SnapshotRootRow: View {
    let count: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 14)
            Image(systemName: "books.vertical")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 15)
            Text("知识库根目录")
                .font(.sn(11, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(count)
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
        }
        .foregroundStyle(SNColor.blue)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(SNColor.blueSoft)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        .padding(.horizontal, 8)
    }
}

private struct SnapshotFolderRow: View {
    let title: String
    let count: String
    var depth = 0
    var expanded = false
    var isSelected = false

    var body: some View {
        HStack(spacing: 5) {
            Color.clear
                .frame(width: CGFloat(depth) * 14)
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8))
                .frame(width: 14)
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .font(.system(size: 11))
                .frame(width: 15)
            Text(title)
                .font(.sn(11, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
            Spacer()
            Text(count)
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
        }
        .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        .padding(.horizontal, 8)
    }
}

private struct SnapshotTreeMaterialRow: View {
    let title: String
    var depth = 0
    var isSelected = false

    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: CGFloat(depth) * 14 + 16)
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 14)
            Text(title)
                .font(.sn(11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(SNColor.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "globe")
                .font(.system(size: 9))
                .foregroundStyle(SNColor.muted.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(isSelected ? SNColor.blueSoft : SNColor.white)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        .padding(.horizontal, 8)
    }
}

private struct SnapshotOutline: View {
    private let headings = [
        ("认知负荷理论与学习设计", 1),
        ("三种认知负荷", 2),
        ("负荷类型与设计动作", 2),
        ("本节要点", 2),
        ("进一步核对", 2)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("目录")
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.ink)
                .padding(.horizontal, 14)
                .frame(height: 44)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(headings.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 4) {
                        Text(item.0)
                            .font(.sn(11, weight: index == 0 ? .medium : .regular))
                            .foregroundStyle(index == 0 ? SNColor.ink : SNColor.text)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(item.1 - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(SNColor.blue.opacity(0.75))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .background(SNColor.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
    }
}

private struct SnapshotReader: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SnapshotReaderTool(title: "材料栏", systemImage: "list.bullet.indent")
                Image(systemName: "books.vertical")
                    .font(.system(size: 12))
                    .foregroundStyle(SNColor.muted)
                Text("学习科学 / 认知负荷理论与学习设计")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(1)
                Spacer()
                SnapshotReaderTool(title: "目录", systemImage: "list.bullet.rectangle")
                SnapshotReaderTool(title: "搜索", systemImage: "magnifyingglass")
                SnapshotReaderTool(title: "编辑副本", systemImage: "square.and.pencil")
                SnapshotReaderTool(title: "版本", systemImage: "clock.arrow.circlepath")
                Rectangle()
                    .fill(SNColor.border)
                    .frame(width: 1, height: 20)
                SnapshotReaderTool(title: "收起研读层", systemImage: "sidebar.right")
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("认知负荷理论与学习设计")
                    .font(.sn(30, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                HStack(spacing: 6) {
                    Text("Markdown 笔记")
                    Text("·")
                    Text("更新于 今天 10:42")
                    Text("·")
                    Text("学习科学")
                }
                .font(.sn(11))
                .foregroundStyle(SNColor.muted)
                .padding(.top, 8)

                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.vertical, 22)

                MarkdownRenderer(markdown: SampleSnapshotContent.markdown, blockSpacing: 14)
            }
            .frame(maxWidth: 648, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .background(SNColor.white)
    }
}

private struct SnapshotReaderTool: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
            Text(title)
                .font(.sn(10))
        }
        .foregroundStyle(SNColor.muted.opacity(0.72))
        .padding(.horizontal, 6)
        .frame(height: 28)
    }
}

private struct SnapshotStudyPanel: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("研读层")
                    .font(.sn(15, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            HStack(spacing: 18) {
                VStack(spacing: 7) {
                    Text("标注")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                    Rectangle()
                        .fill(SNColor.blue)
                        .frame(height: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
                .frame(minWidth: 42)

                VStack(spacing: 7) {
                    Text("AI 研读")
                        .font(.sn(11))
                        .foregroundStyle(SNColor.muted)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                }
                .frame(minWidth: 42)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("03")
                            .font(.sn(11, weight: .medium))
                            .foregroundStyle(Color(red: 0.55, green: 0.33, blue: 0.0))
                        Spacer()
                    }

                    Text("“有效设计应降低无关负荷，并为生成性加工留出空间。”")
                        .font(.snReading(12))
                        .foregroundStyle(SNColor.text)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("关键不只是减少内容，而是让注意力进入关系建构。")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .background(Color(red: 1.0, green: 0.984, blue: 0.937))
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.yellowLine, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("02")
                            .font(.sn(10, weight: .medium))
                            .foregroundStyle(SNColor.text)
                        Spacer()
                        Text("10月31日 09:18")
                            .font(.sn(9))
                            .foregroundStyle(SNColor.muted)
                    }
                    Text("“外在负荷由不恰当的呈现方式产生。”")
                        .font(.snReading(12))
                        .foregroundStyle(SNColor.text)
                        .lineSpacing(3)
                    Text("分段呈现与减少装饰性信息。")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                }
                .padding(10)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text("向 AI 提问当前选段")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                    Text("示例预览 · 实际请求会先确认发送范围")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                    HStack {
                        Image(systemName: "text.quote")
                        Text("解释这段内容与外在负荷的关系")
                        Spacer()
                    }
                    .font(.sn(10))
                    .foregroundStyle(SNColor.text)
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(SNColor.border, lineWidth: 1)
                    }

                    HStack {
                        Spacer()
                        Label("解释选段", systemImage: "sparkles")
                            .font(.sn(10, weight: .medium))
                            .foregroundStyle(SNColor.onAccent)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(SNColor.blue)
                            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    }
                }
                .padding(12)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }
            }
            .padding(14)

            Spacer(minLength: 0)
        }
        .background(SNColor.white)
    }
}

private enum SampleSnapshotContent {
    static let markdown = """
    认知负荷理论关注工作记忆在学习过程中的限制。教学设计的目标并不是一味减少信息，而是把有限的学习资源引向与图式建构相关的活动。

    ## 三种认知负荷

    - **内在负荷**：来自材料本身的复杂性。
    - **外在负荷**：由不恰当的呈现方式产生。
    - **生成性负荷**：用于图式建构和迁移。

    | 负荷类型 | 主要来源 | 设计动作 |
    | :--- | :--- | ---: |
    | 内在负荷 | 材料复杂度 | 分段 |
    | 外在负荷 | 呈现方式 | 降噪 |
    | 生成性负荷 | 学习活动 | 反馈 |

    > 有效设计应降低无关负荷，并为生成性加工留出空间。

    因此，图文整合、分段呈现与及时反馈需要共同服务于概念之间的关系，而不是停留在视觉层面的整齐。

    理解这三种负荷的作用机制，有助于在教学设计中做出合理取舍。关键不是简单地追求“更少的内容”，而是通过适合的呈现与活动设计，让有限的认知资源更多地服务于知识的深入理解和灵活应用。

    ## 本节要点

    1. 三种负荷共同影响学习者的认知资源分配。
    2. 降低无关负荷并不等于删掉所有复杂内容。

    ## 进一步核对

    1. 当前的图文结构是否把注意力引向概念关系？
    2. 装饰性信息是否挤占了生成性加工的空间？
    3. 分段、反馈与练习是否服务于同一学习目标？
    """
}
