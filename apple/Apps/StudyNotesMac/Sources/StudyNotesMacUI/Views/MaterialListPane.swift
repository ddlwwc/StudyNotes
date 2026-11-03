import StudyNotesKit
import SwiftUI

struct MaterialListPane: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            if let actionNotice = model.actionNotice {
                actionNoticeBanner(actionNotice)
            }

            HStack(spacing: 8) {
                Text(selectionSummary)
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(model.hasSelection ? SNColor.blue : SNColor.text)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(resultSummary)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
        .onChange(of: model.selectedMaterialIDs) {
            Task {
                await model.selectionDidChange()
            }
        }
        .onChange(of: model.searchText) {
            Task {
                await model.searchDidChange()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: model.scopeSystemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SNColor.blue)

                Text(model.scopeTitle)
                    .font(.sn(15, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(1)

                Spacer()
            }

            Text(model.scopeSubtitle)
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(SNColor.muted)

            TextField("搜索标题、文件夹或标签", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.sn(11))
                .foregroundStyle(SNColor.text)
                    .disabled(!model.isConnected || model.isLoadingIndex)

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.muted)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
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
    }

    private func actionNoticeBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.sn(10))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                model.dismissActionNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭操作提示")
        }
        .foregroundStyle(SNColor.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SNColor.greenSoft)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConnected {
            emptyState(
                systemImage: "tray",
                title: "连接学习目录后显示材料",
                detail: nil
            )
        } else if model.isLoadingIndex && model.filteredMaterials.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在读取索引")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.filteredMaterials.isEmpty {
            emptyState(
                systemImage: emptyStateImage,
                title: emptyStateTitle,
                detail: emptyStateDetail
            )
        } else {
            List(selection: $model.selectedMaterialIDs) {
                ForEach(model.filteredMaterials) { material in
                    MaterialRow(
                        material: material,
                        isSelected: model.selectedMaterialIDs.contains(material.id),
                        knowledgeBaseName: knowledgeBaseName(for: material.knowledgeBaseID)
                    )
                    .tag(material.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SNColor.white)
            .environment(\.defaultMinListRowHeight, 76)
            .disabled(model.isLoadingIndex)
        }
    }

    private func emptyState(
        systemImage: String,
        title: String,
        detail: String?
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(SNColor.muted)
            Text(title)
                .font(.sn(11))
                .foregroundStyle(SNColor.muted)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                    .multilineTextAlignment(.center)
            }

            if model.searchText.isEmpty,
               model.selectedCollection != .inbox,
               model.selectedCollection != .recycleBin,
               model.canCreateNote {
                Button("新建 Markdown 笔记") {
                    model.presentCreateNoteSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var selectionSummary: String {
        if model.selectedMaterialIDs.isEmpty {
            return "全部 \(model.filteredMaterials.count)"
        }
        if model.selectedMaterialIDs.count == 1 {
            return "已选择 1 篇"
        }
        return "已选择 \(model.selectedMaterialIDs.count) 篇"
    }

    private var resultSummary: String {
        if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(model.filteredMaterials.count) 个结果"
        }
        return model.isRecycleScope ? "删除时间" : "最近更新"
    }

    private var emptyStateImage: String {
        if !model.searchText.isEmpty {
            return "magnifyingglass"
        }
        return switch model.selectedCollection {
        case .inbox:
            "inbox"
        case .recycleBin:
            "trash"
        case .tag:
            "tag"
        default:
            "doc.text"
        }
    }

    private var emptyStateTitle: String {
        if !model.searchText.isEmpty {
            return "没有匹配的材料"
        }
        return switch model.selectedCollection {
        case .inbox:
            "收件箱为空"
        case .recycleBin:
            "回收站为空"
        case .tag:
            "没有使用此标签的材料"
        default:
            "暂无学习材料"
        }
    }

    private var emptyStateDetail: String? {
        if !model.searchText.isEmpty {
            return nil
        }
        return switch model.selectedCollection {
        case .inbox:
            "从材料工具栏使用“移动”即可把所选材料整理进知识库或文件夹。"
        case .recycleBin:
            "移入回收站的材料会保留 30 天，不会自动永久删除。"
        default:
            nil
        }
    }

    private func knowledgeBaseName(for id: UUID?) -> String? {
        guard let id else {
            return nil
        }
        return model.knowledgeBases.first { $0.id == id }?.name
    }
}

private struct MaterialRow: View {
    let material: StudyMaterialSummary
    let isSelected: Bool
    let knowledgeBaseName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? SNColor.white.opacity(0.18) : SNColor.blueSoft)
                Image(systemName: material.deletedAt == nil ? "doc.text" : "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? SNColor.white : SNColor.blue)
            }
            .frame(width: 24, height: 24)
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(SNColor.blueLine, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(material.title)
                    .font(.sn(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SNColor.white : SNColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                folderLine

                if let deletedAt = material.deletedAt {
                    recycleLine(deletedAt: deletedAt)
                }

                Text(tagLine)
                    .font(.sn(9))
                    .foregroundStyle(isSelected ? SNColor.white.opacity(0.82) : SNColor.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
                .padding(.leading, 46)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var folderLine: some View {
        HStack(spacing: 4) {
            if let folderLabel {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                Text(folderLabel)
                if material.deletedAt == nil {
                    Text("·")
                }
            }
            if material.deletedAt == nil {
                Text(WorkspaceFormatting.updatedDate(material.updatedAt))
            }
        }
        .font(.sn(9))
        .foregroundStyle(metadataColor)
        .lineLimit(1)
    }

    private func recycleLine(deletedAt: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 8))
            Text("删除于 \(WorkspaceFormatting.updatedDate(deletedAt))")
            Text("·")
            Text(WorkspaceFormatting.recycleExpiryLabel(deletedAt: deletedAt))
                .fontWeight(
                    WorkspaceFormatting.recycleRemainingDays(deletedAt: deletedAt) == 0
                        ? .semibold
                        : .regular
                )
        }
        .font(.sn(9))
        .foregroundStyle(metadataColor)
        .lineLimit(1)
    }

    private var folderLabel: String? {
        if material.knowledgeBaseID != nil {
            if material.folderPath.isEmpty {
                return knowledgeBaseName ?? "原知识库"
            }
            return "\(knowledgeBaseName ?? "原知识库") / \(WorkspaceFormatting.folderPathDisplay(material.folderPath))"
        }
        return "收件箱"
    }

    private var tagLine: String {
        material.tags.isEmpty
            ? "无标签"
            : material.tags.map { "#\($0)" }.joined(separator: "  ")
    }

    private var metadataColor: Color {
        if isSelected {
            return SNColor.white.opacity(0.8)
        }
        if let deletedAt = material.deletedAt,
           WorkspaceFormatting.recycleRemainingDays(deletedAt: deletedAt) == 0 {
            return SNColor.red
        }
        return SNColor.muted
    }

    private var accessibilityDescription: String {
        var parts = [material.title]
        if let folderLabel {
            parts.append(folderLabel)
        }
        if !material.tags.isEmpty {
            parts.append("标签 \(material.tags.joined(separator: "、"))")
        }
        if let deletedAt = material.deletedAt {
            parts.append(WorkspaceFormatting.recycleExpiryLabel(deletedAt: deletedAt))
        }
        return parts.joined(separator: "，")
    }
}
