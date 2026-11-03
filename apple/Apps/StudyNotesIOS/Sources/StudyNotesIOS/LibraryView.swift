#if os(iOS)
import SwiftUI
import StudyNotesIOSCore

struct LibraryView: View {
    @Bindable var model: IOSAppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isRegularWidth {
                regularWorkspace
            } else {
                compactWorkspace
            }
        }
        .onAppear(perform: syncLayout)
        .onChange(of: horizontalSizeClass) {
            syncLayout()
        }
    }

    private var regularWorkspace: some View {
        HStack(spacing: 0) {
            NavigationStack {
                LibraryRootPane(model: model)
                    .navigationTitle("资料库")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .frame(width: 220)

            Divider()

            NavigationStack {
                DirectoryPane(model: model)
            }
            .frame(minWidth: 280, idealWidth: 330, maxWidth: 370)

            Divider()

            NavigationStack {
                MaterialDetailPane(model: model)
            }
            .frame(maxWidth: .infinity)
        }
        .background(SNColor.page)
    }

    private var compactWorkspace: some View {
        NavigationStack {
            if model.workspace.materialID != nil {
                MaterialDetailPane(model: model)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.navigateBack()
                            } label: {
                                Label("返回", systemImage: "chevron.left")
                            }
                        }
                    }
            } else if selectedKnowledgeBase != nil {
                DirectoryPane(model: model)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.navigateBack()
                            } label: {
                                Label("返回", systemImage: "chevron.left")
                            }
                        }
                    }
            } else {
                LibraryRootPane(model: model)
                    .navigationTitle("资料库")
            }
        }
    }

    private var selectedKnowledgeBase: KnowledgeBaseSummary? {
        guard let id = model.workspace.knowledgeBaseID else {
            return nil
        }
        return model.snapshot.knowledgeBases.first { $0.id == id }
    }

    private func syncLayout() {
        model.updateWorkspaceLayout(isRegular: isRegularWidth)
    }
}

private struct LibraryRootPane: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(
                        systemName: model.isICloud
                            ? "icloud.fill"
                            : "iphone"
                    )
                    .foregroundStyle(
                        model.isICloud ? SNColor.green : SNColor.primary
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.rootState.label)
                            .font(.system(size: 12, weight: .medium))
                        Text(
                            model.isICloud
                                ? "目录与元数据已同步，正文按需下载"
                                : "当前使用本地目录"
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(SNColor.muted)
                    }
                }
            }

            Section("我的知识库") {
                if model.snapshot.knowledgeBases.isEmpty {
                    ContentUnavailableView(
                        "还没有知识库",
                        systemImage: "books.vertical",
                        description: Text("知识库由 Mac 创建，iOS 可整理其中的文件夹与材料。")
                    )
                } else {
                    ForEach(model.snapshot.knowledgeBases) { knowledgeBase in
                        Button {
                            model.selectKnowledgeBase(knowledgeBase.id)
                        } label: {
                            KnowledgeBaseRow(
                                knowledgeBase: knowledgeBase,
                                materials: model.snapshot.materials.filter {
                                    $0.manifest.knowledgeBaseID == knowledgeBase.id
                                },
                                folders: model.snapshot.folders.filter {
                                    $0.knowledgeBaseID == knowledgeBase.id
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button {
                    model.showingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .foregroundStyle(SNColor.ink)
                }
            } footer: {
                Text("学习目录、AI、发布边界、凭据与阅读偏好。")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await model.reloadAll()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.reloadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .accessibilityLabel("刷新资料库")
            }
        }
    }
}

private struct KnowledgeBaseRow: View {
    let knowledgeBase: KnowledgeBaseSummary
    let materials: [LibraryMaterial]
    let folders: [IOSFolder]

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "books.vertical.fill")
                .foregroundStyle(SNColor.primary)
                .frame(width: 34, height: 34)
                .background(SNColor.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(knowledgeBase.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Text("\(materials.count) 份材料 · \(folders.count) 个文件夹")
                    .font(.system(size: 10))
                    .foregroundStyle(SNColor.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SNColor.muted)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct DirectoryPane: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        Group {
            if let knowledgeBase = selectedKnowledgeBase {
                DirectoryBrowser(
                    model: model,
                    knowledgeBase: knowledgeBase,
                    folderPath: model.workspace.folderPath
                )
            } else {
                ContentUnavailableView(
                    "选择一个知识库",
                    systemImage: "books.vertical",
                    description: Text("文件夹和材料会显示在这里。")
                )
            }
        }
    }

    private var selectedKnowledgeBase: KnowledgeBaseSummary? {
        guard let id = model.workspace.knowledgeBaseID else {
            return nil
        }
        return model.snapshot.knowledgeBases.first { $0.id == id }
    }
}

private struct DirectoryBrowser: View {
    @Bindable var model: IOSAppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let knowledgeBase: KnowledgeBaseSummary
    let folderPath: String

    @State private var folderEditor: FolderEditorRequest?
    @State private var moveDialog: MoveDialogRequest?
    @State private var folderToDelete: FolderNode?
    @State private var showingDeleteConfirmation = false

    private var title: String {
        if folderPath.isEmpty {
            return knowledgeBase.name
        }
        return model.folder(
            at: folderPath,
            in: knowledgeBase
        )?.name ?? knowledgeBase.name
    }

    private var childFolders: [FolderNode] {
        model.childFolders(
            in: knowledgeBase,
            folderPath: folderPath
        )
    }

    private var materials: [LibraryMaterial] {
        model.materials(
            in: knowledgeBase,
            folderPath: folderPath
        )
    }

    var body: some View {
        List {
            Section {
                breadcrumb
            }

            if !childFolders.isEmpty {
                Section("文件夹") {
                    ForEach(childFolders) { folder in
                        folderRow(folder)
                    }
                }
            }

            Section("材料") {
                if materials.isEmpty, childFolders.isEmpty {
                    ContentUnavailableView(
                        "文件夹为空",
                        systemImage: "folder",
                        description: Text("使用右上角菜单新建文件夹或 Markdown 笔记。")
                    )
                } else if materials.isEmpty {
                    Text("当前文件夹没有直接材料。")
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.muted)
                } else {
                    ForEach(materials) { material in
                        materialRow(material)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("新建文件夹", systemImage: "folder.badge.plus") {
                        folderEditor = FolderEditorRequest(
                            mode: .create(parentPath: folderPath)
                        )
                    }
                    Button(
                        "新建 Markdown 笔记",
                        systemImage: "square.and.pencil"
                    ) {
                        Task {
                            await model.createMarkdownNote(
                                in: knowledgeBase.id,
                                folderPath: folderPath
                            )
                        }
                    }
                    if let folder = model.folder(
                        at: folderPath,
                        in: knowledgeBase
                    ) {
                        Divider()
                        Button("重命名文件夹", systemImage: "pencil") {
                            folderEditor = FolderEditorRequest(
                                mode: .rename(folder)
                            )
                        }
                        Button("移动到…", systemImage: "folder.badge.gearshape") {
                            presentFolderMove(folder)
                        }
                        Button(
                            "删除文件夹",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            requestDelete(folder)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("整理菜单")
            }
        }
        .sheet(item: $folderEditor) { request in
            FolderNameSheet(
                model: model,
                knowledgeBase: knowledgeBase,
                request: request
            )
        }
        .sheet(item: $moveDialog) { dialog in
            MoveDestinationSheet(
                title: dialog.title,
                destinations: dialog.destinations,
                onMove: dialog.onMove
            )
        }
        .alert(
            "删除文件夹？",
            isPresented: $showingDeleteConfirmation,
            presenting: folderToDelete
        ) { folder in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    await model.deleteFolder(
                        folder,
                        knowledgeBaseID: knowledgeBase.id
                    )
                }
            }
        } message: { folder in
            Text("“\(folder.name)”及其子文件夹会被删除，包含的材料会移入回收站。")
        }
    }

    @ViewBuilder
    private var breadcrumb: some View {
        let content = HStack(spacing: 6) {
            Button(knowledgeBase.name) {
                model.selectFolder("")
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.primary)
            if !folderPath.isEmpty {
                Text("/")
                    .foregroundStyle(SNColor.muted)
                Text(folderPath)
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))

        if horizontalSizeClass == .regular {
            content.dropDestination(for: String.self) { items, _ in
                drop(items, into: "")
            }
        } else {
            content
        }
    }

    private func drop(_ items: [String], into path: String) -> Bool {
        guard let token = items.first else {
            return false
        }
        let accepted = model.canDrop(
            token,
            into: path,
            knowledgeBaseID: knowledgeBase.id
        )
        if accepted {
            Task {
                _ = await model.handleDrop(
                    token,
                    into: path,
                    knowledgeBaseID: knowledgeBase.id
                )
            }
        }
        return accepted
    }

    @ViewBuilder
    private func folderRow(_ folder: FolderNode) -> some View {
        if horizontalSizeClass == .regular {
            folderRowContent(folder)
                .draggable(folderDragToken(folder))
                .dropDestination(for: String.self) { items, _ in
                    drop(items, into: folder.path)
                }
                .contextMenu {
                    folderMenu(folder)
                }
        } else {
            folderRowContent(folder)
                .contextMenu {
                    folderMenu(folder)
                }
        }
    }

    private func folderRowContent(_ folder: FolderNode) -> some View {
        Button {
            model.selectFolder(folder.path)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(SNColor.primary)
                Text(folder.name)
                    .foregroundStyle(SNColor.ink)
                Spacer()
                Text("\(folder.materialCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(SNColor.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SNColor.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func folderMenu(_ folder: FolderNode) -> some View {
        Button("新建子文件夹", systemImage: "folder.badge.plus") {
            folderEditor = FolderEditorRequest(
                mode: .create(parentPath: folder.path)
            )
        }
        Button("重命名", systemImage: "pencil") {
            folderEditor = FolderEditorRequest(mode: .rename(folder))
        }
        Button("移动到…", systemImage: "folder.badge.gearshape") {
            presentFolderMove(folder)
        }
        Button("新建 Markdown 笔记", systemImage: "square.and.pencil") {
            Task {
                await model.createMarkdownNote(
                    in: knowledgeBase.id,
                    folderPath: folder.path
                )
            }
        }
        Divider()
        Button("删除文件夹", systemImage: "trash", role: .destructive) {
            requestDelete(folder)
        }
    }

    @ViewBuilder
    private func materialRow(_ material: LibraryMaterial) -> some View {
        if horizontalSizeClass == .regular {
            materialRowContent(material)
                .draggable("material:\(material.id.uuidString)")
                .contextMenu {
                    materialMenu(material)
                }
        } else {
            materialRowContent(material)
                .contextMenu {
                    materialMenu(material)
                }
        }
    }

    private func materialRowContent(_ material: LibraryMaterial) -> some View {
        Button {
            model.selectMaterial(material.id)
        } label: {
            MaterialListRow(material: material)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func materialMenu(_ material: LibraryMaterial) -> some View {
        Button("打开", systemImage: "book") {
            model.selectMaterial(material.id)
        }
        Button("移动到…", systemImage: "folder.badge.gearshape") {
            presentMaterialMove(material)
        }
        Divider()
        Button(
            "移入回收站",
            systemImage: "trash",
            role: .destructive
        ) {
            Task {
                await model.moveMaterialToRecycleBin(material.id)
            }
        }
    }

    private func folderDragToken(_ folder: FolderNode) -> String {
        "folder:\(knowledgeBase.id.uuidString):\(folder.path)"
    }

    private func presentFolderMove(_ folder: FolderNode) {
        let destinations = model.moveDestinations(
            for: knowledgeBase.id
        ).filter {
            IOSWorkspaceState.isValidFolderMove(
                sourcePath: folder.path,
                targetParentPath: $0.folderPath
            )
        }
        moveDialog = MoveDialogRequest(
            title: "移动“\(folder.name)”",
            destinations: destinations
        ) { destination in
            try await model.moveFolderByForm(
                folder,
                knowledgeBaseID: knowledgeBase.id,
                toParentPath: destination.folderPath
            )
        }
    }

    private func presentMaterialMove(_ material: LibraryMaterial) {
        moveDialog = MoveDialogRequest(
            title: "移动“\(material.title)”",
            destinations: model.materialMoveDestinations()
        ) { destination in
            try await model.moveMaterial(
                material.id,
                toKnowledgeBaseID: destination.knowledgeBaseID,
                folderPath: destination.folderPath
            )
        }
    }

    private func requestDelete(_ folder: FolderNode) {
        folderToDelete = folder
        showingDeleteConfirmation = true
    }
}

private struct MaterialListRow: View {
    let material: LibraryMaterial

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: materialIcon)
                .foregroundStyle(SNColor.primary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(material.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(2)
                Text(material.kind.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(SNColor.muted)
            }
            Spacer()
            AccessStatePill(state: material.accessState)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var materialIcon: String {
        switch material.kind {
        case .image:
            "photo"
        case .pdf:
            "doc.richtext"
        case .note:
            "note.text"
        default:
            "doc.text"
        }
    }
}

private struct MaterialDetailPane: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        if let materialID = model.workspace.materialID {
            MaterialDestinationView(
                model: model,
                materialID: materialID
            )
            .id(materialID)
        } else {
            ContentUnavailableView(
                "选择学习材料",
                systemImage: "book.closed",
                description: Text("阅读与编辑会显示在这里，不打开重复页面。")
            )
            .navigationTitle("阅读")
        }
    }
}

private struct FolderEditorRequest: Identifiable {
    enum Mode {
        case create(parentPath: String)
        case rename(FolderNode)
    }

    let id = UUID()
    let mode: Mode
}

private struct FolderNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: IOSAppModel
    let knowledgeBase: KnowledgeBaseSummary
    let request: FolderEditorRequest

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("文件夹名称") {
                    TextField("名称", text: $name)
                        .textInputAutocapitalization(.never)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        save()
                    }
                    .disabled(
                        isSaving
                            || name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
            }
            .onAppear(perform: configure)
        }
    }

    private var title: String {
        switch request.mode {
        case .create:
            "新建文件夹"
        case .rename:
            "重命名文件夹"
        }
    }

    private func configure() {
        guard name.isEmpty else {
            return
        }
        if case let .rename(folder) = request.mode {
            name = folder.name
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                switch request.mode {
                case let .create(parentPath):
                    _ = try await model.createFolder(
                        named: name,
                        in: knowledgeBase.id,
                        parentPath: parentPath
                    )
                case let .rename(folder):
                    _ = try await model.renameFolder(
                        folder,
                        knowledgeBaseID: knowledgeBase.id,
                        to: name
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct MoveDialogRequest: Identifiable {
    let id = UUID()
    let title: String
    let destinations: [WorkspaceMoveDestination]
    let onMove: (WorkspaceMoveDestination) async throws -> Void
}

private struct MoveDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let destinations: [WorkspaceMoveDestination]
    let onMove: (WorkspaceMoveDestination) async throws -> Void

    @State private var selectedID: String?
    @State private var errorMessage: String?
    @State private var isMoving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if destinations.isEmpty {
                        Text("没有可用的目标位置。")
                            .foregroundStyle(SNColor.muted)
                    } else {
                        ForEach(destinations) { destination in
                            Button {
                                selectedID = destination.id
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(SNColor.primary)
                                    Text(destination.title)
                                        .foregroundStyle(SNColor.ink)
                                    Spacer()
                                    if selectedID == destination.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SNColor.primary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isMoving ? "移动中" : "移动") {
                        move()
                    }
                    .disabled(isMoving || selectedDestination == nil)
                }
            }
            .onAppear {
                if selectedID == nil {
                    selectedID = destinations.first?.id
                }
            }
        }
    }

    private var selectedDestination: WorkspaceMoveDestination? {
        destinations.first { $0.id == selectedID }
    }

    private func move() {
        guard let selectedDestination else {
            return
        }
        isMoving = true
        errorMessage = nil
        Task {
            do {
                try await onMove(selectedDestination)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isMoving = false
            }
        }
    }
}

struct MaterialDestinationView: View {
    @Bindable var model: IOSAppModel
    let materialID: UUID
    @State private var isPreparing = false
    @State private var loadError: String?
    @State private var didStart = false

    var body: some View {
        Group {
            if let material = model.material(id: materialID),
               material.accessState == .downloaded
                || material.accessState == .offline {
                ReaderView(model: model, materialID: materialID)
            } else if isPreparing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在按需下载正文")
                        .font(.system(size: 12))
                        .foregroundStyle(SNColor.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SNColor.nav)
            } else if let loadError {
                VStack(spacing: 14) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 30))
                        .foregroundStyle(SNColor.muted)
                    Text(loadError)
                        .font(.system(size: 12))
                        .foregroundStyle(SNColor.text)
                        .multilineTextAlignment(.center)
                    Button("重试下载") {
                        Task { await prepare() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.primary)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SNColor.nav)
            } else {
                ProgressView()
                    .task {
                        guard !didStart else {
                            return
                        }
                        didStart = true
                        if let material = model.material(id: materialID),
                           material.accessState == .metadataOnly {
                            await prepare()
                        }
                    }
            }
        }
        .onAppear {
            if model.workspace.materialID != materialID {
                model.selectMaterial(materialID)
            }
        }
    }

    private func prepare() async {
        guard !isPreparing else {
            return
        }
        isPreparing = true
        loadError = nil
        await model.download(materialID: materialID)
        isPreparing = false
        if let material = model.material(id: materialID),
           material.accessState == .metadataOnly
            || model.errorMessage != nil {
            loadError = model.errorMessage ?? "正文下载失败。"
            model.errorMessage = nil
        }
    }
}

struct AccessStatePill: View {
    let state: MaterialAccessState

    var body: some View {
        switch state {
        case .offline:
            StatusPill(
                text: "已离线",
                color: SNColor.green,
                background: SNColor.greenSoft,
                systemImage: "checkmark.circle"
            )
        case .downloaded:
            StatusPill(
                text: "已下载",
                color: SNColor.primary,
                background: SNColor.primarySoft,
                systemImage: "arrow.down.circle"
            )
        case .metadataOnly:
            StatusPill(
                text: "按需下载",
                color: SNColor.text,
                background: SNColor.nav,
                systemImage: "cloud"
            )
        case .downloading:
            StatusPill(
                text: "下载中",
                color: SNColor.primary,
                background: SNColor.primarySoft,
                systemImage: "arrow.down.circle"
            )
        case .failed:
            StatusPill(
                text: "下载失败",
                color: SNColor.amberInk,
                background: SNColor.amberSoft,
                systemImage: "exclamationmark.circle"
            )
        }
    }
}
#endif
