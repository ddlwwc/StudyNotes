import StudyNotesKit
import SwiftUI

struct WorkspaceSidebar: View {
    @Bindable var model: WorkspaceModel
    @State private var deletionRequest: SidebarDeletionRequest?

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    sidebarSectionTitle("开始")

                    SidebarNavigationRow(
                        title: "全部材料",
                        systemImage: "tray.full",
                        count: model.materials.count,
                        isSelected: !model.isShowingSettings
                            && model.selectedCollection == .all,
                        isEnabled: model.isConnected
                    ) {
                        Task {
                            await model.selectCollection(.all)
                        }
                    }

                    SidebarNavigationRow(
                        title: "收件箱",
                        systemImage: "tray",
                        count: model.inboxMaterials.count,
                        isSelected: !model.isShowingSettings
                            && model.selectedCollection == .inbox,
                        isEnabled: model.isConnected
                    ) {
                        Task {
                            await model.selectInbox()
                        }
                    }

                    SidebarNavigationRow(
                        title: "回收站",
                        systemImage: "trash",
                        count: model.recycledMaterials.count,
                        isSelected: !model.isShowingSettings
                            && model.selectedCollection == .recycleBin,
                        isEnabled: model.isConnected
                    ) {
                        Task {
                            await model.selectRecycleBin()
                        }
                    }

                    Divider()
                        .overlay(SNColor.border)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)

                    HStack {
                        Text("我的知识库")
                            .font(.sn(11, weight: .medium))
                            .foregroundStyle(SNColor.muted)
                        Spacer()
                        Text("\(model.knowledgeBases.count)")
                            .font(.sn(10))
                            .foregroundStyle(SNColor.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                    if model.knowledgeBases.isEmpty {
                        Text(model.isConnected ? "还没有知识库" : "连接目录后显示知识库")
                            .font(.sn(11))
                            .foregroundStyle(SNColor.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(model.knowledgeBases) { knowledgeBase in
                            knowledgeBaseGroup(knowledgeBase)
                        }
                    }

                    if !model.tags.isEmpty {
                        Divider()
                            .overlay(SNColor.border)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)

                        sidebarSectionTitle("标签")

                        ForEach(model.tags, id: \.self) { tag in
                            SidebarNavigationRow(
                                title: tag,
                                systemImage: "tag",
                                count: model.tagMaterialCount(tag),
                                isSelected: !model.isShowingSettings
                                    && model.selectedCollection == .tag(tag),
                                isEnabled: true
                            ) {
                                Task {
                                    await model.selectTag(tag)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .disabled(model.isLoadingIndex)

            WorkspaceSidebarFooter(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.nav)
        .alert(item: $deletionRequest) { request in
            deletionAlert(for: request)
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 5) {
            Text("知识库")
                .font(.sn(18, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            Spacer(minLength: 4)

            Button {
                model.presentCreateKnowledgeBaseSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.text)
            .disabled(
                !model.isConnected
                    || model.isPerformingAction
                    || model.isShowingSettings
            )
            .help("新建知识库")
            .accessibilityLabel("新建知识库")
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func knowledgeBaseGroup(_ knowledgeBase: KnowledgeBase) -> some View {
        if model.isShowingSettings {
            knowledgeBaseRow(knowledgeBase)
        } else {
            knowledgeBaseRow(knowledgeBase)
                .contextMenu {
                    Button("重命名知识库…") {
                        model.renameRequest = .knowledgeBase(knowledgeBase)
                    }
                    Divider()
                    Button("删除知识库…", role: .destructive) {
                        deletionRequest = .knowledgeBase(knowledgeBase)
                    }
                }
        }
    }

    private func knowledgeBaseRow(_ knowledgeBase: KnowledgeBase) -> some View {
        SidebarNavigationRow(
            title: knowledgeBase.name,
            systemImage: "books.vertical",
            count: model.materialCount(inKnowledgeBase: knowledgeBase.id),
            isSelected: !model.isShowingSettings
                && model.selectedKnowledgeBaseID == knowledgeBase.id,
            isEnabled: true
        ) {
            Task {
                await model.selectKnowledgeBase(knowledgeBase.id)
            }
        }
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.sn(11, weight: .medium))
            .foregroundStyle(SNColor.muted)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }

    private func deletionAlert(for request: SidebarDeletionRequest) -> Alert {
        switch request {
        case let .knowledgeBase(knowledgeBase):
            Alert(
                title: Text("删除知识库“\(knowledgeBase.name)”？"),
                message: Text("知识库内的材料会移入回收站，可在 30 天内恢复。此操作不会永久删除材料。"),
                primaryButton: .destructive(Text("删除知识库")) {
                    Task {
                        await model.deleteKnowledgeBase(knowledgeBase)
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case let .folder(folder):
            Alert(
                title: Text("删除文件夹“\(folder.name)”？"),
                message: Text("文件夹及其子文件夹中的材料会移入回收站，可在 30 天内恢复。"),
                primaryButton: .destructive(Text("删除文件夹")) {
                    Task {
                        await model.deleteFolder(folder)
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }
}

private enum SidebarDeletionRequest: Identifiable {
    case knowledgeBase(KnowledgeBase)
    case folder(KnowledgeFolder)

    var id: String {
        switch self {
        case let .knowledgeBase(knowledgeBase):
            "knowledge-base-\(knowledgeBase.id.uuidString)"
        case let .folder(folder):
            "folder-\(folder.id)"
        }
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    var count: Int?
    var isSelected = false
    var isEnabled = true
    var indentation = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

                Spacer(minLength: 4)

                if let count {
                    Text("\(count)")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(isSelected ? SNColor.blueSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
        .accessibilityLabel(title)
    }
}

private struct WorkspaceSidebarFooter: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Task {
                    await model.openSettings()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16)
                    Text("设置")
                        .font(.sn(12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .foregroundStyle(
                    model.isShowingSettings ? SNColor.blue : SNColor.text
                )
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    model.isShowingSettings ? SNColor.blueSoft : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityValue(
                model.isShowingSettings ? model.settingsPage.title : ""
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            HStack(spacing: 7) {
                statusIndicator
                Text(statusTitle)
                    .font(.sn(9, weight: .medium))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 28)
            .help(model.connectionDetail)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch model.connectionState {
        case .connected:
            Circle()
                .fill(SNColor.green)
                .frame(width: 6, height: 6)
        case .failed:
            Circle()
                .fill(SNColor.red)
                .frame(width: 6, height: 6)
        case .restoring, .connecting:
            ProgressView()
                .controlSize(.mini)
        case .disconnected:
            Circle()
                .fill(SNColor.muted)
                .frame(width: 6, height: 6)
        }
    }

    private var statusTitle: String {
        switch model.connectionState {
        case let .connected(location):
            "\(location.storageKind.label) · 已连接"
        case .failed:
            "目录连接失败"
        case .restoring:
            "正在恢复目录"
        case .connecting:
            "正在加载"
        case .disconnected:
            "选择学习目录"
        }
    }

}
