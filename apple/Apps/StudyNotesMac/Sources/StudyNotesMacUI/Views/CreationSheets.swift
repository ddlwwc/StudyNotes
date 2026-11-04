import StudyNotesKit
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

            FormFieldLabel("名称")
                .padding(.top, 24)

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
                .padding(.top, 7)

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.createKnowledgeBase(named: name) {
                            dismiss()
                        }
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
    @State private var destination: NoteDestination
    @State private var selectedFolderPath: String
    @State private var tagsText = ""
    @State private var markdown = """
    # 新笔记

    从这里开始记录你的想法。
    """

    private enum Field {
        case title
        case tags
        case body
    }

    private enum NoteDestination: Hashable {
        case inbox
        case knowledgeBase(UUID)
    }

    init(model: WorkspaceModel) {
        self.model = model
        let target = model.createNoteTarget
        let initialDestination: NoteDestination = if target?.knowledgeBaseID == nil,
                                                     model.selectedCollection == .inbox {
            .inbox
        } else if let knowledgeBaseID = target?.knowledgeBaseID
            ?? model.defaultKnowledgeBaseIDForCreation {
            .knowledgeBase(knowledgeBaseID)
        } else {
            .inbox
        }
        _destination = State(initialValue: initialDestination)
        _selectedFolderPath = State(
            initialValue: target?.folderPath ?? model.defaultFolderPathForCreation
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "新建 Markdown 笔记",
                subtitle: "可直接保存到知识库文件夹，或先放入收件箱稍后整理。"
            )

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    FormFieldLabel("标题")

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

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        FormFieldLabel("目标位置")

                        Picker("目标位置", selection: $destination) {
                            Text("收件箱")
                                .tag(NoteDestination.inbox)
                            ForEach(model.knowledgeBases) { knowledgeBase in
                                Text(knowledgeBase.name)
                                    .tag(NoteDestination.knowledgeBase(knowledgeBase.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let knowledgeBaseID {
                        VStack(alignment: .leading, spacing: 7) {
                            FormFieldLabel("文件夹")

                            Picker("文件夹", selection: $selectedFolderPath) {
                                Text("知识库根目录")
                                    .tag("")
                                ForEach(model.folders(in: knowledgeBaseID)) { folder in
                                    Text(folderOptionLabel(folder))
                                        .tag(folder.path)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    FormFieldLabel("初始标签")

                    TextField("用逗号分隔，例如：Swift, 并发", text: $tagsText)
                        .textFieldStyle(.plain)
                        .font(.sn(12))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(SNColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: SNRadius.control)
                                .stroke(
                                    focusedField == .tags ? SNColor.blue : SNColor.border,
                                    lineWidth: 1
                                )
                        }
                        .focused($focusedField, equals: .tags)

                    if !parsedTags.isEmpty {
                        TagPreview(tags: parsedTags)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        FormFieldLabel("Markdown 正文")
                        Spacer()
                        Text("UTF-8")
                            .font(.sn(9))
                            .foregroundStyle(SNColor.muted)
                    }

                    TextEditor(text: $markdown)
                        .font(
                            .custom(
                                model.readingPreferences.codeFont,
                                size: max(11, model.readingPreferences.fontSize - 4)
                            )
                        )
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
                        .frame(
                            maxWidth: CGFloat(model.readingPreferences.lineWidth),
                            alignment: .leading
                        )
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
                    Task {
                        if await createNote() {
                            dismiss()
                        }
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
        .frame(width: 680, height: 700)
        .background(SNColor.panel)
        .onAppear {
            focusedField = .title
        }
        .onChange(of: destination) {
            selectedFolderPath = ""
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var knowledgeBaseID: UUID? {
        guard case let .knowledgeBase(id) = destination else {
            return nil
        }
        return id
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isPerformingAction
    }

    private var parsedTags: [String] {
        parseTagList(tagsText)
    }

    private func createNote() async -> Bool {
        switch destination {
        case .inbox:
            await model.createInboxMarkdownNote(
                title: title,
                markdown: markdown,
                tags: parsedTags
            )
        case let .knowledgeBase(knowledgeBaseID):
            await model.createMarkdownNote(
                title: title,
                markdown: markdown,
                in: knowledgeBaseID,
                folderPath: selectedFolderPath,
                tags: parsedTags
            )
        }
    }

    private func folderOptionLabel(_ folder: KnowledgeFolder) -> String {
        String(
            repeating: "　",
            count: max(0, folder.depth - 1)
        ) + folder.name
    }
}

struct CreateFolderSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    let request: WorkspaceCreateFolderRequest
    @FocusState private var isNameFocused: Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "新建文件夹",
                subtitle: "文件夹可以继续嵌套，并用于组织知识库内的材料。"
            )

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("位置")

                HStack(spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.blue)
                    Text(parentLocationLabel)
                        .font(.sn(11))
                        .foregroundStyle(SNColor.text)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(SNColor.nav)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("名称")

                TextField("例如：图论", text: $name)
                    .textFieldStyle(.plain)
                    .font(.sn(13))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(
                                isNameFocused ? SNColor.blue : SNColor.border,
                                lineWidth: 1
                            )
                    }
                    .focused($isNameFocused)
            }
            .padding(.top, 16)

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.red)
                    .padding(.top, 8)
            }

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.createFolder(
                            named: name,
                            in: request.knowledgeBaseID,
                            parentPath: request.parentPath
                        ) {
                            dismiss()
                        }
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
        .frame(width: 470, height: 350)
        .background(SNColor.panel)
        .onAppear {
            model.dismissError()
            isNameFocused = true
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parentLocationLabel: String {
        let knowledgeBaseName = model.knowledgeBases.first {
            $0.id == request.knowledgeBaseID
        }?.name ?? "知识库"
        guard !request.parentPath.isEmpty else {
            return "\(knowledgeBaseName) / 根目录"
        }
        return "\(knowledgeBaseName) / \(WorkspaceFormatting.folderPathDisplay(request.parentPath))"
    }
}

struct RenameWorkspaceItemSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    let target: WorkspaceRenameTarget
    @FocusState private var isNameFocused: Bool
    @State private var name: String

    init(model: WorkspaceModel, target: WorkspaceRenameTarget) {
        self.model = model
        self.target = target
        let initialName: String
        switch target {
        case let .knowledgeBase(knowledgeBase):
            initialName = knowledgeBase.name
        case let .folder(folder):
            initialName = folder.name
        }
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: title,
                subtitle: "名称会立即更新到学习目录索引。"
            )

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("名称")

                TextField("名称", text: $name)
                    .textFieldStyle(.plain)
                    .font(.sn(13))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(
                                isNameFocused ? SNColor.blue : SNColor.border,
                                lineWidth: 1
                            )
                    }
                    .focused($isNameFocused)
            }
            .padding(.top, 24)

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.red)
                    .padding(.top, 8)
            }

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await rename() {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("保存")
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
        .frame(width: 460, height: 300)
        .background(SNColor.panel)
        .onAppear {
            model.dismissError()
            isNameFocused = true
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var title: String {
        switch target {
        case .knowledgeBase:
            "重命名知识库"
        case .folder:
            "重命名文件夹"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rename() async -> Bool {
        switch target {
        case let .knowledgeBase(knowledgeBase):
            await model.renameKnowledgeBase(id: knowledgeBase.id, to: trimmedName)
        case let .folder(folder):
            await model.renameFolder(folder, to: trimmedName)
        }
    }
}

struct MoveFolderSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    let request: WorkspaceMoveFolderRequest
    @State private var targetParentPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "移动文件夹",
                subtitle: "只能移动同一知识库内的文件夹，不能移动到自身或子文件夹中。"
            )

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("文件夹")

                HStack(spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(SNColor.blue)
                    Text(request.folder.name)
                        .font(.sn(12, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                    Spacer()
                    Text(WorkspaceFormatting.folderPathDisplay(request.folder.path))
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(SNColor.nav)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("目标父文件夹")

                Picker("目标父文件夹", selection: $targetParentPath) {
                    Text("知识库根目录")
                        .tag("")
                    ForEach(
                        model.folderOptions(
                            in: request.folder.knowledgeBaseID,
                            excluding: request.folder
                        )
                    ) { folder in
                        Text(folderOptionLabel(folder))
                            .tag(folder.path)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 16)

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.moveFolder(
                            request.folder,
                            toParentPath: targetParentPath
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("移动")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.isPerformingAction
                        || targetParentPath == request.folder.parentPath
                )
            }
        }
        .padding(24)
        .frame(width: 500, height: 330)
        .background(SNColor.panel)
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private func folderOptionLabel(_ folder: KnowledgeFolder) -> String {
        String(repeating: "　", count: max(0, folder.depth - 1)) + folder.name
    }
}

struct MoveMaterialsSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var targetKnowledgeBaseID: UUID?
    @State private var targetFolderPath = ""

    init(model: WorkspaceModel) {
        self.model = model
        _targetKnowledgeBaseID = State(
            initialValue: model.selectedKnowledgeBaseID
                ?? model.knowledgeBases.first?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "移动所选材料",
                subtitle: "材料会移动到目标知识库的根目录或指定文件夹。"
            )

            selectionSummary
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    FormFieldLabel("目标知识库")

                    Picker("目标知识库", selection: $targetKnowledgeBaseID) {
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
                    FormFieldLabel("目标文件夹")

                    Picker("目标文件夹", selection: $targetFolderPath) {
                        Text("知识库根目录")
                            .tag("")
                        ForEach(targetFolders) { folder in
                            Text(folderOptionLabel(folder))
                                .tag(folder.path)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(targetKnowledgeBaseID == nil)
                }
            }
            .padding(.top, 18)

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await move() {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 66)
                    } else {
                        Text("移动")
                            .frame(width: 66)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    targetKnowledgeBaseID == nil
                        || model.selectedMaterialIDs.isEmpty
                        || model.isPerformingAction
                )
            }
        }
        .padding(24)
        .frame(width: 520, height: 460)
        .background(SNColor.panel)
        .onChange(of: targetKnowledgeBaseID) {
            targetFolderPath = ""
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("将移动 \(model.selectedMaterialIDs.count) 篇材料")
                .font(.sn(12, weight: .medium))
                .foregroundStyle(SNColor.ink)
            Text(selectedTitles)
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SNColor.nav)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
    }

    private var selectedTitles: String {
        model.selectedMaterials.map(\.title).joined(separator: "、")
    }

    private var targetFolders: [KnowledgeFolder] {
        guard let targetKnowledgeBaseID else {
            return []
        }
        return model.folders(in: targetKnowledgeBaseID)
    }

    private func folderOptionLabel(_ folder: KnowledgeFolder) -> String {
        String(repeating: "　", count: max(0, folder.depth - 1)) + folder.name
    }

    private func move() async -> Bool {
        guard let targetKnowledgeBaseID else {
            return false
        }
        return await model.moveSelectedMaterials(
            toKnowledgeBaseID: targetKnowledgeBaseID,
            folderPath: targetFolderPath
        )
    }
}

struct EditTagsSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTagsFocused: Bool
    @State private var mode: WorkspaceTagMutationMode = .add
    @State private var tagsText: String

    init(model: WorkspaceModel) {
        self.model = model
        _tagsText = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "编辑所选标签",
                subtitle: "可以给每篇材料添加或移除标签，也可以显式替换全部标签。"
            )

            Text("\(model.selectedMaterialIDs.count) 篇材料")
                .font(.sn(11, weight: .medium))
                .foregroundStyle(SNColor.text)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("操作")

                Picker("操作", selection: $mode) {
                    ForEach(WorkspaceTagMutationMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 7) {
                FormFieldLabel("标签")

                TextField("用逗号分隔，例如：Swift, 并发", text: $tagsText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.sn(12))
                    .lineLimit(2...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(
                                isTagsFocused ? SNColor.blue : SNColor.border,
                                lineWidth: 1
                            )
                    }
                    .focused($isTagsFocused)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("预览")
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                    Spacer()
                    Text(previewSummary)
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                }

                ScrollView {
                    TagPreview(tags: parsedTags)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 120)
            }
            .padding(.top, 16)

            Spacer()

            SheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.applyTagMutation(parsedTags, mode: mode) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 66)
                    } else {
                        Text("保存标签")
                            .frame(width: 66)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isPerformingAction || !model.canEditSelectionTags)
            }
        }
        .padding(24)
        .frame(width: 520, height: 390)
        .background(SNColor.panel)
        .onAppear {
            isTagsFocused = true
        }
        .onChange(of: mode) {
            tagsText = mode == .add
                ? ""
                : model.selectedTagsForEditing.joined(separator: ", ")
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var parsedTags: [String] {
        parseTagList(tagsText)
    }

    private var previewSummary: String {
        if mode == .replace, parsedTags.isEmpty {
            return "保存后会清除全部标签"
        }
        return "\(parsedTags.count) 个标签"
    }
}

private struct FormFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.sn(11, weight: .medium))
            .foregroundStyle(SNColor.text)
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

private struct TagPreview: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            Text("无标签")
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
                .padding(.vertical, 4)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 64), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(tags, id: \.self) { tag in
                    Text("# \(tag)")
                        .font(.sn(9, weight: .medium))
                        .foregroundStyle(SNColor.blue)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(SNColor.blueSoft)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
                }
            }
        }
    }
}

private func parseTagList(_ text: String) -> [String] {
    var tags: [String] = []
    var seen = Set<String>()

    for rawTag in text.split(whereSeparator: {
        $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" || $0 == "\n"
    }) {
        var tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") {
            tag.removeFirst()
        }
        guard !tag.isEmpty else {
            continue
        }
        let key = tag.lowercased()
        if seen.insert(key).inserted {
            tags.append(tag)
        }
    }
    return tags
}
