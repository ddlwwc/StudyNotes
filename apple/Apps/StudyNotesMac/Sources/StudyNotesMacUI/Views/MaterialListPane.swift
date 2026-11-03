import StudyNotesKit
import SwiftUI

struct MaterialListPane: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(model.scopeTitle)
                        .font(.sn(15, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                        .lineLimit(1)

                    Spacer()
                }

                Text("知识库 / \(model.knowledgeBases.count) 个分类")
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

                TextField("搜索当前材料", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.sn(11))
                    .foregroundStyle(SNColor.text)
                    .disabled(!model.isConnected)

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

            HStack {
                Text("全部 \(model.filteredMaterials.count)")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.blue)
                Spacer()
                Text("最近更新")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
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
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConnected {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(SNColor.muted)
                Text("连接学习目录后显示材料")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else if model.filteredMaterials.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: model.searchText.isEmpty ? "doc.text" : "magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(SNColor.muted)
                Text(model.searchText.isEmpty ? "暂无学习材料" : "没有匹配的材料")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.muted)

                if model.searchText.isEmpty, model.canCreateNote {
                    Button("新建 Markdown 笔记") {
                        model.presentCreateNoteSheet()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.filteredMaterials) { material in
                        MaterialRow(
                            material: material,
                            isSelected: model.selectedMaterialID == material.id
                        ) {
                            Task {
                                await model.selectMaterial(material.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MaterialRow: View {
    let material: StudyMaterialSummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? SNColor.white : SNColor.blueSoft)
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SNColor.blue)
                }
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(SNColor.blueLine, lineWidth: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(material.title)
                        .font(.sn(12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? SNColor.ink : SNColor.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Text("Markdown 笔记")
                        Text("·")
                        Text(WorkspaceFormatting.updatedDate(material.updatedAt))

                        if !material.conflictCopies.isEmpty {
                            Text("· \(material.conflictCopies.count) 个冲突副本")
                                .foregroundStyle(SNColor.red)
                        }
                    }
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.leading, isSelected ? 13 : 16)
            .padding(.trailing, 12)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(isSelected ? SNColor.blueSoft : SNColor.white)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(SNColor.blue)
                        .frame(width: 3)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(material.title)，Markdown 笔记")
    }
}
