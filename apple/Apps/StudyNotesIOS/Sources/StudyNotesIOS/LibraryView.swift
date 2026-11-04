#if os(iOS)
import Foundation
import SwiftUI
import StudyNotesIOSCore
import UniformTypeIdentifiers

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if let knowledgeBase = selectedKnowledgeBase {
                if horizontalSizeClass == .regular {
                    UnifiedDirectoryBrowser(
                        model: model,
                        knowledgeBase: knowledgeBase
                    )
                } else {
                    DirectoryBrowser(
                        model: model,
                        knowledgeBase: knowledgeBase,
                        folderPath: model.workspace.folderPath
                    )
                }
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

private struct UnifiedDirectoryBrowser: View {
    @Bindable var model: IOSAppModel
    let knowledgeBase: KnowledgeBaseSummary

    @State private var folderEditor: FolderEditorRequest?
    @State private var moveDialog: MoveDialogRequest?
    @State private var folderToDelete: FolderNode?
    @State private var showingDeleteConfirmation = false
    @State private var showingFileImporter = false
    @State private var isSelectingMaterials = false
    @State private var dropTargetPath: String?
    @State private var activeDragToken: String?

    private var targetFolderPath: String {
        model.workspace.folderPath
    }

    private var targetFolder: FolderNode? {
        model.folder(at: targetFolderPath, in: knowledgeBase)
    }

    private var searchMaterials: [LibraryMaterial] {
        var seen = Set<UUID>()
        return model.searchHits.compactMap { hit in
            guard seen.insert(hit.materialID).inserted else {
                return nil
            }
            guard let material = model.material(id: hit.materialID),
                  material.manifest.knowledgeBaseID == knowledgeBase.id else {
                return nil
            }
            return material
        }.sorted {
            $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
    }

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
                Section("搜索结果") {
                    if searchMaterials.isEmpty {
                        Text("没有匹配的学习材料")
                            .font(.system(size: 12))
                            .foregroundStyle(SNColor.muted)
                    } else {
                        ForEach(searchMaterials) { material in
                            Button {
                                model.selectMaterial(material.id)
                            } label: {
                                UnifiedSearchResultRow(material: material)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ForEach(model.treeRows(in: knowledgeBase)) { row in
                    treeRow(row)
                }
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索材料、正文、标注与 AI 结果"
        )
        .onChange(of: model.searchText) {
            model.scheduleSearch()
            if !isSearching {
                model.restoreTreeAfterSearch()
            }
        }
        .navigationTitle(knowledgeBase.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelectingMaterials {
                    Text("已选 \(model.workspace.selectedMaterialIDs.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                }
                Button {
                    isSelectingMaterials.toggle()
                } label: {
                    Image(
                        systemName: isSelectingMaterials
                            ? "checkmark.circle.fill"
                            : "checkmark.circle"
                    )
                }
                .accessibilityLabel(
                    isSelectingMaterials ? "完成材料选择" : "选择材料"
                )

                Menu {
                    Button("新建文件夹", systemImage: "folder.badge.plus") {
                        folderEditor = FolderEditorRequest(
                            mode: .create(parentPath: targetFolderPath)
                        )
                    }
                    Button(
                        "新建 Markdown 笔记",
                        systemImage: "square.and.pencil"
                    ) {
                        Task {
                            await model.createMarkdownNote(
                                in: knowledgeBase.id,
                                folderPath: targetFolderPath
                            )
                        }
                    }
                    Button("导入学习材料", systemImage: "square.and.arrow.down") {
                        showingFileImporter = true
                    }
                    if let targetFolder {
                        Divider()
                        Button("重命名文件夹", systemImage: "pencil") {
                            folderEditor = FolderEditorRequest(
                                mode: .rename(targetFolder)
                            )
                        }
                        Button("移动到…", systemImage: "folder.badge.gearshape") {
                            presentFolderMove(targetFolder)
                        }
                        Button(
                            "删除文件夹",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            requestDelete(targetFolder)
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
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .html, .data],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else {
                return
            }
            Task {
                await model.importMaterials(
                    from: urls,
                    in: knowledgeBase.id,
                    folderPath: targetFolderPath
                )
            }
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
    private func treeRow(_ row: LibraryTreeRow) -> some View {
        switch row {
        case let .root(_, count, isExpanded):
            rootRow(
                count: count,
                isExpanded: isExpanded
            )
        case let .folder(folder, depth, isExpanded):
            folderRow(
                folder,
                depth: depth,
                isExpanded: isExpanded
            )
        case let .material(material, depth):
            materialRow(material, depth: depth)
        }
    }

    private func rootRow(
        count: Int,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                model.toggleTreeFolder("")
            } label: {
                Image(
                    systemName: isExpanded
                        ? "chevron.down"
                        : "chevron.right"
                )
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起知识库根目录" : "展开知识库根目录")

            Button {
                model.selectTreeFolder("")
                isSelectingMaterials = false
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(SNColor.primary)
                    Text(knowledgeBase.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                        .lineLimit(1)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(SNColor.muted)
                }
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .background(
            rowBackground(
                isTarget: dropTargetPath == "",
                isSelected: model.workspace.folderPath.isEmpty
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: "")
        } isTargeted: { targeted in
            updateDropTarget("", targeted: targeted)
        }
        .contextMenu {
            rootMenu
        }
        .listRowInsets(
            EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)
        )
        .listRowSeparator(.hidden)
    }

    private func folderRow(
        _ folder: FolderNode,
        depth: Int,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                model.toggleTreeFolder(folder.path)
            } label: {
                Image(
                    systemName: isExpanded
                        ? "chevron.down"
                        : "chevron.right"
                )
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isExpanded
                    ? "收起\(folder.name)"
                    : "展开\(folder.name)"
            )

            Button {
                model.selectTreeFolder(folder.path)
                isSelectingMaterials = false
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                        .foregroundStyle(SNColor.primary)
                    Text(folder.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                        .lineLimit(1)
                    Spacer()
                    Text("\(folder.materialCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(SNColor.muted)
                }
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 15 + 4)
        .padding(.trailing, 8)
        .background(
            rowBackground(
                isTarget: dropTargetPath == folder.path,
                isSelected: model.workspace.folderPath == folder.path
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrag {
            let token = model.folderDragToken(
                for: folder,
                knowledgeBaseID: knowledgeBase.id
            )
            activeDragToken = token
            return NSItemProvider(object: token as NSString)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: folder.path)
        } isTargeted: { targeted in
            updateDropTarget(
                folder.path,
                targeted: targeted,
                expandsOnHover: !isExpanded
            )
        }
        .contextMenu {
            folderMenu(folder)
        }
        .listRowInsets(
            EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)
        )
        .listRowSeparator(.hidden)
    }

    private func materialRow(
        _ material: LibraryMaterial,
        depth: Int
    ) -> some View {
        Button {
            if isSelectingMaterials {
                model.toggleTreeMaterialSelection(material.id)
            } else {
                model.selectMaterial(material.id)
            }
        } label: {
            UnifiedTreeMaterialRow(
                material: material,
                isSelected: model.workspace.selectedMaterialIDs.contains(
                    material.id
                )
            )
            .padding(.leading, CGFloat(depth) * 15 + 24)
        }
        .buttonStyle(.plain)
        .onDrag {
            let token = model.materialDragToken(
                for: material,
                knowledgeBaseID: knowledgeBase.id
            )
            activeDragToken = token
            return NSItemProvider(object: token as NSString)
        }
        .contextMenu {
            materialMenu(material)
        }
        .listRowInsets(
            EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        )
        .listRowSeparator(.hidden)
    }

    private func rowBackground(
        isTarget: Bool,
        isSelected: Bool = false
    ) -> Color {
        if isTarget {
            return SNColor.primarySoft
        }
        if isSelected {
            return SNColor.nav
        }
        return .clear
    }

    private func updateDropTarget(
        _ path: String,
        targeted: Bool,
        expandsOnHover: Bool = false
    ) {
        guard targeted,
              let token = activeDragToken,
              model.canDrop(
                  token,
                  into: path,
                  knowledgeBaseID: knowledgeBase.id
              ) else {
            dropTargetPath = nil
            return
        }
        dropTargetPath = path
        guard expandsOnHover else {
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard dropTargetPath == path else {
                return
            }
            model.toggleTreeFolder(path)
        }
    }

    private func drop(_ items: [String], into path: String) -> Bool {
        guard let token = items.first,
              model.canDrop(
                token,
                into: path,
                knowledgeBaseID: knowledgeBase.id
              ) else {
            activeDragToken = nil
            return false
        }
        activeDragToken = nil
        dropTargetPath = nil
        Task {
            _ = await model.handleDrop(
                token,
                into: path,
                knowledgeBaseID: knowledgeBase.id
            )
        }
        return true
    }

    @ViewBuilder
    private var rootMenu: some View {
        Button("新建文件夹", systemImage: "folder.badge.plus") {
            folderEditor = FolderEditorRequest(mode: .create(parentPath: ""))
        }
        Button("新建 Markdown 笔记", systemImage: "square.and.pencil") {
            Task {
                await model.createMarkdownNote(
                    in: knowledgeBase.id,
                    folderPath: ""
                )
            }
        }
        Button("导入学习材料", systemImage: "square.and.arrow.down") {
            model.selectTreeFolder("")
            showingFileImporter = true
        }
    }

    @ViewBuilder
    private func folderMenu(_ folder: FolderNode) -> some View {
        Button("新建子文件夹", systemImage: "folder.badge.plus") {
            folderEditor = FolderEditorRequest(
                mode: .create(parentPath: folder.path)
            )
        }
        Button("新建 Markdown 笔记", systemImage: "square.and.pencil") {
            Task {
                await model.createMarkdownNote(
                    in: knowledgeBase.id,
                    folderPath: folder.path
                )
            }
        }
        Button("导入学习材料", systemImage: "square.and.arrow.down") {
            model.selectTreeFolder(folder.path)
            showingFileImporter = true
        }
        Divider()
        Button("重命名", systemImage: "pencil") {
            folderEditor = FolderEditorRequest(mode: .rename(folder))
        }
        Button("移动到…", systemImage: "folder.badge.gearshape") {
            presentFolderMove(folder)
        }
        Button("删除文件夹", systemImage: "trash", role: .destructive) {
            requestDelete(folder)
        }
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

private struct UnifiedTreeMaterialRow: View {
    let material: LibraryMaterial
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: materialIcon)
                .font(.system(size: 12))
                .foregroundStyle(SNColor.primary)
                .frame(width: 18)
            Text(material.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SNColor.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !material.conflictCopies.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(SNColor.amberInk)
                    .accessibilityLabel("存在文件冲突")
            }
            Image(systemName: "globe")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    material.publishMapping == nil
                        ? SNColor.muted.opacity(0.6)
                        : SNColor.primary
                )
                .accessibilityLabel(
                    material.publishMapping == nil
                        ? "未发布到 Web"
                        : "已发布到 Web"
                )
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(
            isSelected ? SNColor.primarySoft : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            [
                material.kind.label,
                "更新于 \(material.manifest.updatedAt.formatted(date: .abbreviated, time: .omitted))",
                material.tags.isEmpty
                    ? "无标签"
                    : "标签：\(material.tags.joined(separator: "、"))"
            ].joined(separator: "，")
        )
    }

    private var materialIcon: String {
        switch material.kind {
        case .image:
            "photo"
        case .pdf:
            "doc.richtext"
        case .note:
            "note.text"
        case .html, .webArticle:
            "globe"
        default:
            "doc.text"
        }
    }
}

private struct UnifiedSearchResultRow: View {
    let material: LibraryMaterial

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(SNColor.primary)
                Text(material.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(1)
            }
            Text(pathLabel)
                .font(.system(size: 10))
                .foregroundStyle(SNColor.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .frame(minHeight: 46, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var pathLabel: String {
        if material.folderPath.isEmpty {
            return "\(material.knowledgeBaseName) / 知识库根目录"
        }
        return "\(material.knowledgeBaseName) / "
            + material.folderPath.replacingOccurrences(of: "/", with: " / ")
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
