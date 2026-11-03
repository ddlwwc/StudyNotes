import SwiftUI

struct StudyPanel: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("研读层")
                    .font(.sn(15, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.isStudyPanelVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(SNColor.muted)
                .help("收起研读层")
                .accessibilityLabel("收起研读层")
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            HStack(spacing: 18) {
                ForEach(StudyPanelTab.allCases) { tab in
                    Button {
                        model.studyPanelTab = tab
                    } label: {
                        VStack(spacing: 7) {
                            Text(tab.title)
                                .font(.sn(11, weight: model.studyPanelTab == tab ? .medium : .regular))
                                .foregroundStyle(model.studyPanelTab == tab ? SNColor.ink : SNColor.muted)

                            Rectangle()
                                .fill(model.studyPanelTab == tab ? SNColor.blue : Color.clear)
                                .frame(height: 2)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                        }
                        .frame(minWidth: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            ScrollView {
                Group {
                    if model.studyPanelTab == .annotations {
                        annotationContent
                    } else {
                        aiContent
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.panel)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var annotationContent: some View {
        if model.selectedNote == nil {
            StudyPanelEmptyState(
                systemImage: "text.badge.xmark",
                title: "未打开笔记",
                description: "选择一篇笔记后，研读层会显示它对应的标注。"
            )
        } else {
            StudyPanelEmptyState(
                systemImage: "tag",
                title: "当前笔记还没有标注",
                description: "StudyNotesKit 尚未提供标注读写 API，这里不会展示示例标注。"
            )
        }
    }

    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudyPanelEmptyState(
                systemImage: "sparkles",
                title: "AI 研读尚未配置",
                description: "接入供应商与密钥后才能发送当前笔记或选段。"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("向 AI 提问当前笔记")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.ink)

                Text("AI 请求尚未接入，不会发送任何内容。")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)

                TextEditor(text: .constant(""))
                    .font(.sn(11))
                    .disabled(true)
                    .frame(height: 70)
                    .padding(6)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(SNColor.border, lineWidth: 1)
                    }

                Button("解释选段") {}
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.blue)
                    .controlSize(.small)
                    .disabled(true)
                    .help("AI 研读尚未接入")
            }
            .padding(12)
            .background(SNColor.white)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
        }
    }
}
private struct StudyPanelEmptyState: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(SNColor.muted)
            Text(title)
                .font(.sn(11, weight: .medium))
                .foregroundStyle(SNColor.text)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
