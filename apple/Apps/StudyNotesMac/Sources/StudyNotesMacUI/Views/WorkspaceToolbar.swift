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
                    .foregroundStyle(SNColor.white)
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

            Button {
                Task {
                    await model.chooseWorkspace()
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.muted)
            .disabled(model.isPerformingAction || model.isLoadingIndex)
            .help(model.isConnected ? "更换学习目录" : "选择学习目录")
            .accessibilityLabel(model.isConnected ? "更换学习目录" : "选择学习目录")
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

    var body: some View {
        HStack(spacing: 6) {
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

            if !model.hasSelection {
                Button {} label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .font(.sn(11))
                }
                .disabled(true)
                .help("导入功能尚未接入")

                Button {} label: {
                    Label("AI 研读", systemImage: "sparkles")
                        .font(.sn(11))
                }
                .disabled(true)
                .help("AI 研读尚未配置")

                Button {} label: {
                    Label("发布", systemImage: "paperplane")
                        .font(.sn(11))
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .disabled(true)
                .help("发布功能尚未接入")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct WorkspaceSnapshotHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .fill(SNColor.blue)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SNColor.white)
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

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
                    .frame(width: 22, height: 22)
            }

            Spacer()

            HStack(spacing: 6) {
                SnapshotActionPill(title: "导入", systemImage: "square.and.arrow.down", isEnabled: false)
                SnapshotActionPill(title: "新建笔记", systemImage: "square.and.pencil", isEnabled: true)
                SnapshotActionPill(title: "AI 研读", systemImage: "sparkles", isEnabled: false)
                SnapshotActionPill(
                    title: "发布",
                    systemImage: "paperplane",
                    isEnabled: false,
                    isPrimary: true
                )
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
        return isPrimary ? SNColor.white : SNColor.text
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return SNColor.nav
        }
        return isPrimary ? SNColor.blue : SNColor.white
    }
}
