import SwiftUI

struct WorkspaceToolbar: ToolbarContent {
    let model: WorkspaceModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            WorkspaceBrandStatus(model: model)
        }

        ToolbarItem(placement: .primaryAction) {
            WorkspaceToolbarActions(model: model)
        }
    }
}

struct WorkspaceBrandStatus: View {
    let model: WorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .fill(SNColor.blue)
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SNColor.onAccent)
            }
            .frame(width: 30, height: 30)

            Text("StudyNotes")
                .font(.sn(14, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            HStack(spacing: 5) {
                statusIndicator
                Text(model.connectionLabel)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(1)
            }
            .help(model.connectionDetail)
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
}

struct WorkspaceToolbarActions: View {
    let model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            PaneVisibilityButton(
                title: "知识库栏",
                systemImage: "sidebar.left",
                isVisible: model.isLibraryPaneVisible
            ) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    model.togglePane(.library)
                }
            }

            if !model.isShowingSettings {
                PaneVisibilityButton(
                    title: "材料目录栏",
                    systemImage: "list.bullet.indent",
                    isVisible: model.isMaterialPaneVisible
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        model.togglePane(.materials)
                    }
                }
                PaneVisibilityButton(
                    title: "研读层",
                    systemImage: "sidebar.right",
                    isVisible: model.isStudyPanelVisible
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        model.togglePane(.study)
                    }
                }

                Divider()
                    .frame(height: 18)

                if model.isRecycleScope {
                    if model.hasSelection {
                        Text("已选 \(model.selectedMaterialIDs.count) 项")
                            .font(.sn(10, weight: .medium))
                            .foregroundStyle(SNColor.text)

                        Button {
                            Task {
                                await model.restoreSelectedMaterials()
                            }
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                                .font(.sn(11))
                        }
                        .disabled(!model.canRestoreSelection || model.isPerformingAction)
                        .help("优先恢复到删除前位置；原知识库不存在时进入收件箱")
                    }

                    Button {
                        model.isConfirmingPurgeExpired = true
                    } label: {
                        Label("清理已过期", systemImage: "trash.slash")
                            .font(.sn(11))
                    }
                    .disabled(
                        !model.hasExpiredRecycleItems
                            || model.isPerformingAction
                            || model.isLoadingIndex
                    )
                    .help(
                        model.hasExpiredRecycleItems
                            ? "永久清理超过 30 天的材料"
                            : "没有超过 30 天的材料"
                    )

                    Divider()
                        .frame(height: 18)
                } else if model.hasSelection {
                    Text("已选 \(model.selectedMaterialIDs.count) 项")
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.text)

                    Button {
                        model.isShowingMoveMaterials = true
                    } label: {
                        Label("移动", systemImage: "folder")
                            .font(.sn(11))
                    }
                    .disabled(!model.canMoveSelection || model.isPerformingAction)
                    .help("移动所选材料到知识库或文件夹")

                    Button {
                        model.isShowingEditTags = true
                    } label: {
                        Label("标签", systemImage: "tag")
                            .font(.sn(11))
                    }
                    .disabled(!model.canEditSelectionTags || model.isPerformingAction)
                    .help("编辑所选材料的标签")

                    Button {
                        model.isConfirmingRecycle = true
                    } label: {
                        Label("移入回收站", systemImage: "trash")
                            .font(.sn(11))
                    }
                    .disabled(!model.canRecycleSelection || model.isPerformingAction)
                    .help("把所选材料移入回收站")

                    Divider()
                        .frame(height: 18)
                }

                Button {
                    model.presentCreateNoteSheet()
                } label: {
                    Label("新建笔记", systemImage: "square.and.pencil")
                        .font(.sn(11))
                }
                .disabled(!model.canCreateNote || model.isPerformingAction)
                .help(model.canCreateNote ? "新建 Markdown 笔记" : "请先连接学习目录")

                Button {
                    model.presentImportSheet()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .font(.sn(11))
                }
                .disabled(!model.isConnected || model.isPerformingAction)
                .help("导入 Markdown、HTML、PDF、图片或网页文章")

                Button {
                    if model.selectedProvider == nil {
                        Task {
                            await model.openSettings(page: .ai)
                        }
                    } else if model.selectedDocument != nil {
                        model.prepareMaterialSummary()
                    }
                } label: {
                    Label("AI 研读", systemImage: "sparkles")
                        .font(.sn(11))
                }
                .disabled(model.selectedDocument == nil && !model.providerProfiles.isEmpty)
                .help(
                    model.selectedProvider == nil
                        ? "配置 AI 供应商"
                        : "总结整篇材料"
                )

                Button {
                    model.preparePublishPreview()
                } label: {
                    Label("发布", systemImage: "paperplane")
                        .font(.sn(11))
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .disabled(!model.canPreviewPublish || model.isPerformingAction)
                .help(
                    model.canPreviewPublish
                        ? "预览公开正文与私人研读层范围"
                        : "只有文章类材料可以发布"
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct WorkspaceSnapshotHeader: View {
    var showsWorkspaceActions = true

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .fill(SNColor.blue)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SNColor.onAccent)
                }
                .frame(width: 30, height: 30)

                Text("StudyNotes")
                    .font(.sn(14, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                HStack(spacing: 5) {
                    Circle()
                        .fill(SNColor.green)
                        .frame(width: 6, height: 6)
                    Text("iCloud 目录 · 已连接")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.text)
                }
            }

            Spacer()

            if showsWorkspaceActions {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SNColor.blue)
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SNColor.blue)
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SNColor.blue)

                    Rectangle()
                        .fill(SNColor.border)
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 4)

                    SnapshotActionPill(
                        title: "导入",
                        systemImage: "square.and.arrow.down",
                        isEnabled: true
                    )
                    SnapshotActionPill(
                        title: "新建笔记",
                        systemImage: "square.and.pencil",
                        isEnabled: true
                    )
                    SnapshotActionPill(
                        title: "AI 研读",
                        systemImage: "sparkles",
                        isEnabled: true
                    )
                    SnapshotActionPill(
                        title: "发布",
                        systemImage: "paperplane",
                        isEnabled: true,
                        isPrimary: true
                    )
                }
            } else {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SNColor.blue)
                    .frame(width: 28, height: 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: SNMetric.toolbarHeight)
        .background(SNColor.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
        }
    }
}

private struct SnapshotActionPill: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    var isPrimary = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
            Text(title)
                .font(.sn(10, weight: .medium))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        .overlay {
            if !isPrimary {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return SNColor.muted.opacity(0.7)
        }
        return isPrimary ? SNColor.onAccent : SNColor.text
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return SNColor.nav
        }
        return isPrimary ? SNColor.blue : SNColor.white
    }
}
