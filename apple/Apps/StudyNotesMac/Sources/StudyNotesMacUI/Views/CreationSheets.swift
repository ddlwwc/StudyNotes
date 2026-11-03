import SwiftUI

struct CreateKnowledgeBaseSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "新建知识库",
                subtitle: "知识库会作为学习目录中的文件夹保存。"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("名称")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.text)

                TextField("例如：学习科学", text: $name)
                    .textFieldStyle(.plain)
                    .font(.sn(13))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(isNameFocused ? SNColor.blue : SNColor.border, lineWidth: 1)
                    }
                    .focused($isNameFocused)
            }
            .padding(.top, 24)

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        await model.createKnowledgeBase(named: name)
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("创建")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || model.isPerformingAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 260)
        .background(SNColor.panel)
        .onAppear {
            isNameFocused = true
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CreateNoteSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var title = ""
    @State private var selectedKnowledgeBaseID: UUID?
    @State private var markdown = """
    # 新笔记

    从这里开始记录你的想法。
    """

    private enum Field {
        case title
        case body
    }

    init(model: WorkspaceModel) {
        self.model = model
        _selectedKnowledgeBaseID = State(
            initialValue: model.selectedKnowledgeBaseID ?? model.knowledgeBases.first?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "新建 Markdown 笔记",
                subtitle: "笔记会保存到所选知识库，并立即在阅读区打开。"
            )

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("标题")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.text)

                    TextField("笔记标题", text: $title)
                        .textFieldStyle(.plain)
                        .font(.sn(13))
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(SNColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: SNRadius.control)
                                .stroke(
                                    focusedField == .title ? SNColor.blue : SNColor.border,
                                    lineWidth: 1
                                )
                        }
                        .focused($focusedField, equals: .title)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("知识库")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.text)

                    Picker("知识库", selection: $selectedKnowledgeBaseID) {
                        ForEach(model.knowledgeBases) { knowledgeBase in
                            Text(knowledgeBase.name)
                                .tag(Optional(knowledgeBase.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Markdown 正文")
                            .font(.sn(11, weight: .medium))
                            .foregroundStyle(SNColor.text)
                        Spacer()
                        Text("UTF-8")
                            .font(.sn(9))
                            .foregroundStyle(SNColor.muted)
                    }

                    TextEditor(text: $markdown)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(SNColor.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(SNColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: SNRadius.control)
                                .stroke(
                                    focusedField == .body ? SNColor.blue : SNColor.border,
                                    lineWidth: 1
                                )
                        }
                        .focused($focusedField, equals: .body)
                }
            }
            .padding(.top, 20)

            Spacer(minLength: 16)

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    guard let selectedKnowledgeBaseID else {
                        return
                    }
                    Task {
                        await model.createMarkdownNote(
                            title: title,
                            markdown: markdown,
                            in: selectedKnowledgeBaseID
                        )
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 72)
                    } else {
                        Text("创建并打开")
                            .frame(width: 72)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 660, height: 600)
        .background(SNColor.panel)
        .onAppear {
            focusedField = .title
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedKnowledgeBaseID != nil
            && !model.isPerformingAction
    }
}

private struct SheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sn(20, weight: .semibold))
                .foregroundStyle(SNColor.ink)
            Text(subtitle)
                .font(.sn(11))
                .foregroundStyle(SNColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SheetActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
        .padding(.top, 14)
    }
}
