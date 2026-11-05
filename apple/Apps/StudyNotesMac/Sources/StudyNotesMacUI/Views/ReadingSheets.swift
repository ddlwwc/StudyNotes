import StudyNotesKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportMaterialSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURLs: [URL] = []
    @State private var isChoosingFiles = false
    @State private var destinationID: UUID?
    @State private var folderPath = ""
    @State private var tagsText = ""

    init(model: WorkspaceModel) {
        self.model = model
        _destinationID = State(
            initialValue: model.importTarget?.knowledgeBaseID
                ?? model.defaultImportKnowledgeBaseID
        )
        _folderPath = State(
            initialValue: model.importTarget?.folderPath
                ?? model.defaultImportFolderPath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: "导入学习材料",
                subtitle: "支持 Markdown、HTML、PDF 和常见静态图片；原始文件会保持不变。"
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        isChoosingFiles = true
                    } label: {
                        Label("选择文件", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.blue)

                    Button {
                        model.isShowingImport = false
                        dismiss()
                        Task { @MainActor in
                            model.isShowingWebImport = true
                        }
                    } label: {
                        Label("导入网页文章", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }

                GroupBox {
                    if selectedURLs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(SNColor.muted)
                            Text("可一次选择多份文件")
                                .font(.sn(11, weight: .medium))
                                .foregroundStyle(SNColor.text)
                            Text("也可以把文件拖到材料列表。导入时会按内容指纹识别重复材料。")
                                .font(.sn(9))
                                .foregroundStyle(SNColor.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(selectedURLs, id: \.self) { url in
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc")
                                            .foregroundStyle(SNColor.blue)
                                        Text(url.lastPathComponent)
                                            .font(.sn(10))
                                            .foregroundStyle(SNColor.text)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(url.pathExtension.uppercased())
                                            .font(.sn(8, weight: .medium))
                                            .foregroundStyle(SNColor.muted)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 150)
                    }
                }

                destinationFields

                VStack(alignment: .leading, spacing: 6) {
                    ReadingFieldLabel("初始标签")
                    TextField("用逗号分隔，例如：课程, 重点", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.top, 20)

            Spacer()

            ReadingSheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.importFiles(
                            selectedURLs,
                            knowledgeBaseID: destinationID,
                            folderPath: destinationID == nil ? "" : folderPath,
                            tags: parsedTags
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 84)
                    } else {
                        Text("开始导入")
                            .frame(width: 84)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedURLs.isEmpty || model.isPerformingAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 610)
        .background(SNColor.panel)
        .fileImporter(
            isPresented: $isChoosingFiles,
            allowedContentTypes: importContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                selectedURLs = urls
            }
        }
        .onChange(of: destinationID) {
            folderPath = ""
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }

    private var destinationFields: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ReadingFieldLabel("目标位置")
                Picker("目标位置", selection: $destinationID) {
                    Text("收件箱")
                        .tag(Optional<UUID>.none)
                    ForEach(model.knowledgeBases) { knowledgeBase in
                        Text(knowledgeBase.name)
                            .tag(Optional(knowledgeBase.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let destinationID {
                VStack(alignment: .leading, spacing: 6) {
                    ReadingFieldLabel("文件夹")
                    Picker("文件夹", selection: $folderPath) {
                        Text("知识库根目录")
                            .tag("")
                        ForEach(model.folders(in: destinationID)) { folder in
                            Text(String(repeating: "　", count: max(0, folder.depth - 1)) + folder.name)
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
    }

    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { [",", "，", ";", "；", "\n"].contains(String($0)) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var importContentTypes: [UTType] {
        [
            .plainText,
            .html,
            .pdf,
            .png,
            .jpeg,
            .gif,
            .webP,
            .tiff,
            .bmp,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            UTType(filenameExtension: "heic") ?? .image,
            UTType(filenameExtension: "avif") ?? .image
        ]
    }
}

struct WebArticleImportSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var destinationID: UUID?
    @State private var folderPath = ""
    @State private var tagsText = ""

    init(model: WorkspaceModel) {
        self.model = model
        _destinationID = State(
            initialValue: model.importTarget?.knowledgeBaseID
                ?? model.defaultImportKnowledgeBaseID
        )
        _folderPath = State(
            initialValue: model.importTarget?.folderPath
                ?? model.defaultImportFolderPath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: "导入网页文章",
                subtitle: "只抓取一个网页正文，不绕过登录或付费墙；图片会尽量保存到材料包。"
            )

            HStack(spacing: 8) {
                TextField("https://example.com/article", text: $model.webArticleURLText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        await model.fetchWebArticle()
                        title = model.webArticleDraft?.title ?? ""
                    }
                } label: {
                    if model.isFetchingWebArticle {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("提取预览")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .disabled(
                    model.webArticleURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isFetchingWebArticle
                )
            }
            .padding(.top, 20)

            if !model.webArticleStatus.isEmpty {
                Label(
                    model.webArticleStatus,
                    systemImage: model.webArticleDraft == nil ? "arrow.down.circle" : "checkmark.circle"
                )
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)
                .padding(.top, 10)
            }

            if model.webArticleDraft != nil {
                VStack(alignment: .leading, spacing: 7) {
                    ReadingFieldLabel("标题")
                    TextField("文章标题", text: $title)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        ReadingFieldLabel("正文范围")
                        Spacer()
                        Text("可在此调整后导入")
                            .font(.sn(9))
                            .foregroundStyle(SNColor.muted)
                    }
                    .padding(.top, 4)

                    TextEditor(text: $model.webArticleMarkdown)
                        .font(.system(size: 11))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(SNColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: SNRadius.control)
                                .stroke(SNColor.border, lineWidth: 1)
                        }
                }
                .padding(.top, 14)

                destinationEditor
                    .padding(.top, 12)
            } else {
                Spacer()
            }

            Spacer(minLength: 8)

            ReadingSheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.importFetchedWebArticle(
                            title: title,
                            markdown: model.webArticleMarkdown,
                            knowledgeBaseID: destinationID,
                            folderPath: destinationID == nil ? "" : folderPath,
                            tags: parsedTags
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 86)
                    } else {
                        Text("确认导入")
                            .frame(width: 86)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .disabled(
                    model.webArticleDraft == nil
                        || model.webArticleMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isPerformingAction
                )
            }
        }
        .padding(24)
        .frame(width: 760, height: 760)
        .background(SNColor.panel)
        .onChange(of: destinationID) {
            folderPath = ""
        }
        .interactiveDismissDisabled(model.isFetchingWebArticle || model.isPerformingAction)
    }

    private var destinationEditor: some View {
        HStack(spacing: 12) {
            Picker("目标位置", selection: $destinationID) {
                Text("收件箱")
                    .tag(Optional<UUID>.none)
                ForEach(model.knowledgeBases) { knowledgeBase in
                    Text(knowledgeBase.name)
                        .tag(Optional(knowledgeBase.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if let destinationID {
                Picker("文件夹", selection: $folderPath) {
                    Text("知识库根目录")
                        .tag("")
                    ForEach(model.folders(in: destinationID)) { folder in
                        Text(folder.name)
                            .tag(folder.path)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            TextField("标签", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { [",", "，", ";", "；"].contains(String($0)) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct EditReaderCopySheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: "编辑阅读副本",
                subtitle: "保存会更新阅读副本并生成新的文字版本，不会修改不可变原始文件。"
            )

            TextEditor(text: $text)
                .font(
                    .custom(
                        model.readingPreferences.codeFont,
                        size: max(11, model.readingPreferences.fontSize - 4)
                    )
                )
                .lineSpacing(
                    model.readingPreferences.fontSize
                        * (model.readingPreferences.lineHeight - 1)
                )
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }
                .frame(
                    maxWidth: CGFloat(model.readingPreferences.lineWidth),
                    alignment: .leading
                )
                .padding(.top, 18)

            ReadingSheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.saveReaderCopy(text) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 70)
                    } else {
                        Text("保存版本")
                            .frame(width: 70)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isPerformingAction)
            }
        }
        .padding(24)
        .frame(width: 760, height: 700)
        .background(SNColor.panel)
        .onAppear {
            text = model.selectedDocument?.markdown ?? ""
        }
        .interactiveDismissDisabled(model.isPerformingAction)
    }
}

struct VersionHistorySheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: "文字版本",
                subtitle: "只保留最近 10 个版本。恢复操作会生成新的当前版本。"
            )

            if model.revisions.isEmpty {
                ContentUnavailableView(
                    "暂无文字版本",
                    systemImage: "clock",
                    description: Text("保存阅读副本后，这里会出现可恢复的版本。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.revisions) { revision in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(WorkspaceFormatting.updatedDate(revision.createdAt))
                                .font(.sn(11, weight: .medium))
                                .foregroundStyle(SNColor.ink)
                            Text(revision.text)
                                .font(.sn(10))
                                .foregroundStyle(SNColor.muted)
                                .lineLimit(3)
                        }
                        Spacer()
                        Button("恢复") {
                            Task {
                                await model.restoreRevision(revision)
                                dismiss()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.plain)
                .padding(.top, 14)
            }

            ReadingSheetActions {
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .background(SNColor.panel)
    }
}

struct LinkMaterialsSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: "关联学习材料",
                subtitle: "笔记可以关联零份或多份学习材料；关联不会复制或改写对方内容。"
            )

            List {
                ForEach(candidates) { material in
                    Toggle(isOn: binding(for: material.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(material.title)
                                .font(.sn(11, weight: .medium))
                                .foregroundStyle(SNColor.text)
                            Text(material.kind.displayName)
                                .font(.sn(9))
                                .foregroundStyle(SNColor.muted)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .padding(.top, 16)

            ReadingSheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存关联") {
                    Task {
                        await model.setLinkedMaterials(selectedIDs)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 580)
        .background(SNColor.panel)
        .onAppear {
            selectedIDs = Set(model.selectedDocument?.summary.linkedMaterialIDs ?? [])
        }
    }

    private var candidates: [StudyMaterialSummary] {
        model.allActiveMaterials.filter {
            $0.id != model.selectedDocument?.summary.id
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }
}

struct AnnotationEditorSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    let request: AnnotationDraftRequest
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: request.annotationID == nil ? "新建标注" : "编辑标注",
                subtitle: "标注只保存在私人研读层，不会改写原始文件或阅读副本。"
            )

            if !request.quote.isEmpty {
                Text("“\(request.quote)”")
                    .font(.snReading(14))
                    .foregroundStyle(SNColor.text)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SNColor.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .padding(.top, 18)
            } else {
                Label(
                    request.anchor.kind == .imageRect ? "图片矩形区域" : "PDF 页面区域",
                    systemImage: request.anchor.kind == .imageRect
                        ? "rectangle.dashed"
                        : "doc.viewfinder"
                )
                .font(.sn(11, weight: .medium))
                .foregroundStyle(SNColor.text)
                .padding(.top, 18)
            }

            TextEditor(text: $note)
                .font(.sn(12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }
                .frame(height: 150)
                .padding(.top, 12)

            if request.annotationID != nil,
               let existing = model.annotations.first(where: { $0.id == request.annotationID }),
               existing.status == .unresolved,
               let selection = model.readerSelection {
                Button {
                    Task {
                        await model.rebind(existing)
                        dismiss()
                    }
                } label: {
                    Label(
                        "绑定到当前选择：\(selection.quote.isEmpty ? "区域" : selection.quote)",
                        systemImage: "scope"
                    )
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
            }

            Spacer()

            ReadingSheetActions {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        if await model.saveAnnotation(note: note) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 66)
                    } else {
                        Text("保存标注")
                            .frame(width: 66)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isPerformingAction)
            }
        }
        .padding(24)
        .frame(width: 540, height: 470)
        .background(SNColor.panel)
        .onAppear {
            note = request.initialNote
        }
    }
}

struct AIContextConfirmationSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    let preview: AIContextPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingSheetHeader(
                title: preview.origin == .summary ? "确认整篇总结范围" : "确认发送选区",
                subtitle: "只有确认后才会把以下内容发送给外部 AI 供应商。请求失败不会自动重试或切换供应商。"
            )

            HStack(spacing: 18) {
                Label(preview.profile.name, systemImage: "server.rack")
                Label(preview.profile.model, systemImage: "cpu")
                Label("约 \(preview.approximateCharacterCount) 字符", systemImage: "textformat.size")
            }
            .font(.sn(10))
            .foregroundStyle(SNColor.muted)
            .padding(.top, 18)

            Text(preview.prompt)
                .font(.sn(12, weight: .medium))
                .foregroundStyle(SNColor.text)
                .padding(.top, 14)

            Text(preview.context)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SNColor.text)
                .lineLimit(18)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }
                .padding(.top, 10)

            Spacer()

            ReadingSheetActions {
                Button("取消") {
                    model.cancelAIContext()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("确认并发送") {
                    model.confirmAIContext()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 680, height: 560)
        .background(SNColor.panel)
    }
}

struct PublishPreviewSheet: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var publishing = PublishingPanelModel()
    @State private var isConfirmingWithdraw = false
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                ReadingSheetHeader(
                    title: "发布到 Web",
                    subtitle: "发布前确认公开范围；发布使用仅存于 macOS 钥匙串的 Ed25519 私钥签名。"
                )

                Toggle("公开标注与备注", isOn: $model.publishIncludeAnnotations)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.publishIncludeAnnotations) {
                        Task { await model.refreshPublishPreview() }
                    }

                Toggle("公开 AI 研读附录", isOn: $model.publishIncludeAI)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.publishIncludeAI) {
                        Task { await model.refreshPublishPreview() }
                    }

                if let preview = model.publishPreview {
                    GroupBox("本次公开范围") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("正文：\(preview.title)")
                            Text("标注：\(preview.includeAnnotations ? "\(preview.annotations.count) 条" : "隐藏")")
                            Text("AI 研读：\(preview.includeAI ? "公开附录" : "隐藏")")
                            Text("内容指纹：\(preview.contentFingerprint.prefix(16))…")
                            Text("媒体：\(preview.media.count) 项")
                        }
                        .font(.sn(10))
                        .foregroundStyle(SNColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("发布服务") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(publishing.serverURLText)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SNColor.muted)
                                .lineLimit(1)
                            Text(
                                publishing.credentialKid.map {
                                    "本机公钥：\($0)"
                                } ?? "尚未生成发布密钥"
                            )
                            .font(.sn(8))
                            .foregroundStyle(SNColor.muted)
                            .lineLimit(1)
                            Button("管理发布密钥…") {
                                dismiss()
                                Task {
                                    await model.openSettings(page: .credentials)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("发布媒体") {
                        if preview.media.isEmpty {
                            Text("没有需要上传的媒体。")
                                .font(.sn(10))
                                .foregroundStyle(SNColor.muted)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(preview.media) { media in
                                    HStack {
                                        Image(
                                            systemName: mediaStateImage(
                                                publishing.mediaState(for: media)
                                            )
                                        )
                                        .foregroundStyle(
                                            mediaStateColor(
                                                publishing.mediaState(for: media)
                                            )
                                        )
                                        Text(media.fileName)
                                            .font(.sn(9))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(
                                            mediaStateLabel(
                                                publishing.mediaState(for: media)
                                            )
                                        )
                                            .font(.sn(8))
                                            .foregroundStyle(SNColor.muted)
                                    }
                                }
                            }
                            if publishing.hasRetryableMedia {
                                Button("重新检查并重试") {
                                    Task { await publishing.retryMedia() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(
                                    publishing.isBusy
                                        || publishing.credentialKid == nil
                                )
                            }
                        }
                    }

                    GroupBox("可见性与生命周期") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("目标可见性", selection: $publishing.visibility) {
                                ForEach(PublishVisibility.allCases) { visibility in
                                    Text(visibility.title)
                                        .tag(visibility)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Button(
                                    publishing.articleID == nil
                                        ? "发布到 Web"
                                        : "更新 Web 版本"
                                ) {
                                    Task { await publishing.publish() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(SNColor.blue)
                                .disabled(
                                    publishing.isBusy
                                        || publishing.credentialKid == nil
                                )

                                Button("刷新状态") {
                                    Task { await publishing.refreshStatus() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    publishing.isBusy
                                        || publishing.articleID == nil
                                )
                            }
                            .controlSize(.small)

                            HStack {
                                Button("应用可见性") {
                                    Task {
                                        await publishing.changeVisibility(
                                            to: publishing.visibility
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    publishing.isBusy
                                        || publishing.articleID == nil
                                )

                                Button("下架") {
                                    isConfirmingWithdraw = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    publishing.isBusy
                                        || publishing.articleID == nil
                                )
                            }
                            .controlSize(.small)

                            HStack {
                                TextField(
                                    "回滚目标版本",
                                    text: $publishing.rollbackTargetText
                                )
                                .textFieldStyle(.roundedBorder)
                                Button("回滚") {
                                    Task { await publishing.rollback() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    publishing.isBusy
                                        || publishing.articleID == nil
                                        || Int(publishing.rollbackTargetText) == nil
                                )
                            }
                            .controlSize(.small)

                            Button("永久删除 Web 文章", role: .destructive) {
                                isConfirmingDelete = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                publishing.isBusy
                                    || publishing.articleID == nil
                            )
                        }
                        .padding(.top, 4)
                    }

                    if let mapping = preview.mapping {
                        GroupBox("本地轻量发布映射") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("文章：\(mapping.articleID)")
                                Text("版本：\(mapping.lastPublishedVersion ?? "—")")
                                Text("指纹：\(mapping.contentFingerprint.prefix(20))…")
                            }
                            .font(.sn(8))
                            .foregroundStyle(SNColor.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let message = publishing.statusMessage {
                        Text(message)
                            .font(.sn(9, weight: .medium))
                            .foregroundStyle(
                                publishing.hasError ? SNColor.red : SNColor.text
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("关闭") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                }
                .padding(22)
                .frame(width: 430, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: 430)
            .background(SNColor.panel)

            Divider()

            if let preview = model.publishPreview {
                PublishHTMLPreview(html: preview.html)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SNColor.white)
            }
        }
        .frame(width: 1_180, height: 760)
        .onAppear {
            attachPublishingPreview()
            if publishing.rollbackTargetText.isEmpty,
               publishing.expectedVersion > 1 {
                publishing.rollbackTargetText = String(
                    publishing.expectedVersion - 1
                )
            }
        }
        .onChange(of: model.publishPreview) {
            attachPublishingPreview()
        }
        .confirmationDialog(
            "下架这篇 Web 文章？",
            isPresented: $isConfirmingWithdraw
        ) {
            Button("确认下架", role: .destructive) {
                Task { await publishing.withdraw() }
            }
        } message: {
            Text("公开链接与未列出链接都将不可访问。")
        }
        .confirmationDialog(
            "永久删除 Web 文章？",
            isPresented: $isConfirmingDelete
        ) {
            Button("永久删除", role: .destructive) {
                Task { await publishing.deleteArticle() }
            }
        } message: {
            Text("文章、全部版本和无引用媒体会被清理；本机材料不会被删除。")
        }
    }

    private func attachPublishingPreview() {
        guard let preview = model.publishPreview else {
            return
        }
        publishing.attach(
            preview: preview,
            tags: model.selectedDocument?.summary.tags ?? [],
            saveMapping: { mapping in
                await model.saveLocalPublishMapping(
                    articleID: mapping.articleID,
                    publicURLText: mapping.publicURL.absoluteString,
                    version: mapping.lastPublishedVersion ?? "",
                    visibility: mapping.visibility,
                    contentFingerprint: mapping.contentFingerprint
                )
            },
            clearMapping: {
                await model.clearLocalPublishMapping()
            }
        )
    }

    private func mediaStateLabel(_ state: PublishMediaState) -> String {
        switch state {
        case .pendingCredentials:
            "等待服务端上传凭据"
        case .pendingUpload:
            "等待上传"
        case .uploading:
            "上传中"
        case .uploaded:
            "已上传"
        case .failed:
            "上传失败"
        }
    }

    private func mediaStateImage(_ state: PublishMediaState) -> String {
        switch state {
        case .uploaded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.circle.fill"
        case .uploading:
            "arrow.up.circle"
        case .pendingCredentials, .pendingUpload:
            "clock"
        }
    }

    private func mediaStateColor(_ state: PublishMediaState) -> Color {
        switch state {
        case .uploaded:
            SNColor.green
        case .failed:
            SNColor.red
        default:
            SNColor.muted
        }
    }
}

private struct ReadingSheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.sn(20, weight: .semibold))
                .foregroundStyle(SNColor.ink)
            Text(subtitle)
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReadingFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.sn(10, weight: .medium))
            .foregroundStyle(SNColor.text)
    }
}

private struct ReadingSheetActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
        .padding(.top, 12)
    }
}
