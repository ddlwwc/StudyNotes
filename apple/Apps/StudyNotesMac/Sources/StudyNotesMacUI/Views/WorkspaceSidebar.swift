import SwiftUI

struct WorkspaceSidebar: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
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
                .disabled(!model.isConnected || model.isPerformingAction)
                .help("新建知识库")
                .accessibilityLabel("新建知识库")
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("开始")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)

                    SidebarNavigationRow(
                        title: "全部材料",
                        systemImage: "tray.full",
                        count: model.materials.count,
                        isSelected: model.selectedKnowledgeBaseID == nil,
                        isEnabled: model.isConnected
                    ) {
                        Task {
                            await model.selectKnowledgeBase(nil)
                        }
                    }

                    SidebarNavigationRow(
                        title: "收件箱",
                        systemImage: "inbox",
                        detail: "即将推出",
                        isEnabled: false
                    ) {}

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
                            SidebarNavigationRow(
                                title: knowledgeBase.name,
                                systemImage: "books.vertical",
                                count: model.materials.filter {
                                    $0.knowledgeBaseID == knowledgeBase.id
                                }.count,
                                isSelected: model.selectedKnowledgeBaseID == knowledgeBase.id,
                                isEnabled: true
                            ) {
                                Task {
                                    await model.selectKnowledgeBase(knowledgeBase.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            WorkspaceConnectionCard(model: model)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.nav)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    var count: Int?
    var detail: String?
    var isSelected = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                    .frame(width: 16)

                Text(title)
                    .font(.sn(12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let detail {
                    Text(detail)
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                        .lineLimit(1)
                } else if let count {
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

private struct WorkspaceConnectionCard: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Button {
            Task {
                await model.chooseWorkspace()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    statusIndicator

                    Text(statusTitle)
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.text)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if model.isPerformingAction || model.isLoadingIndex {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: model.isConnected ? "arrow.triangle.2.circlepath" : "folder.badge.plus")
                            .font(.system(size: 11))
                            .foregroundStyle(SNColor.muted)
                    }
                }

                Text(model.connectionDetail)
                    .font(.sn(9))
                    .foregroundStyle(isFailure ? SNColor.red : SNColor.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SNColor.white)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isPerformingAction || model.isLoadingIndex)
        .help(model.isConnected ? "更换学习目录" : "选择本地或 iCloud 学习目录")
        .accessibilityLabel(model.isConnected ? "学习目录已连接，点击更换" : "选择学习目录")
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
            "学习目录连接失败"
        case .restoring:
            "正在恢复学习目录"
        case .connecting:
            "正在加载学习目录"
        case .disconnected:
            "选择学习目录"
        }
    }

    private var isFailure: Bool {
        if case .failed = model.connectionState {
            return true
        }
        return false
    }
}
