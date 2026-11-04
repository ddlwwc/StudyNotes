import AppKit
import StudyNotesKit
import SwiftUI

struct MaterialListPane: View {
    @Bindable var model: WorkspaceModel
    @State private var deletionRequest: FolderDeletionRequest?
    @State private var isRootTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if isSearching {
                searchFilters
            }
            if let notice = model.actionNotice {
                noticeBanner(notice)
            }
            summaryBar
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
        .onAppear(perform: revealSelectedFolder)
        .onChange(of: model.selectedCollection) { revealSelectedFolder() }
        .onChange(of: model.selectedMaterialIDs) {
            Task { await model.selectionDidChange() }
        }
        .onChange(of: model.searchText) {
            Task { await model.searchDidChange() }
        }
        .alert(item: $deletionRequest) { request in
            Alert(
                title: Text("删除文件夹“\(request.folder.name)”？"),
                message: Text("文件夹及子文件夹中的材料会移入回收站，可在 30 天内恢复。"),
                primaryButton: .destructive(Text("删除文件夹")) {
                    Task { await model.deleteFolder(request.folder) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
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
            TextField("搜索标题、正文、笔记、标注与 AI", text: $model.searchText)
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

    private var searchFilters: some View {
        HStack(spacing: 6) {
            Menu {
                Button("全部类型") { model.searchKindFilter = nil }
                ForEach(
                    [StudyMaterialKind.note, .markdown, .html, .webArticle, .pdf, .image],
                    id: \.rawValue
                ) { kind in
                    Button(kind.displayName) { model.searchKindFilter = kind }
                }
            } label: {
                Label(
                    model.searchKindFilter?.displayName ?? "全部类型",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(.sn(9))
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button("不限时间") { model.searchUpdatedAfter = nil }
                Button("今天") {
                    model.searchUpdatedAfter = Calendar.current.startOfDay(for: Date())
                }
                Button("最近 7 天") {
                    model.searchUpdatedAfter = Date().addingTimeInterval(-7 * 86_400)
                }
                Button("最近 30 天") {
                    model.searchUpdatedAfter = Date().addingTimeInterval(-30 * 86_400)
                }
            } label: {
                Label(
                    model.searchUpdatedAfter == nil ? "不限时间" : "已筛选时间",
                    systemImage: "calendar"
                )
                .font(.sn(9))
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .onChange(of: model.searchKindFilter) {
            Task { await model.searchDidChange() }
        }
        .onChange(of: model.searchUpdatedAfter) {
            Task { await model.searchDidChange() }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 8) {
            Text(selectionSummary)
                .font(.sn(11, weight: .medium))
                .foregroundStyle(model.hasSelection ? SNColor.blue : SNColor.text)
                .lineLimit(1)
            Spacer()
            Text(resultSummary)
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConnected {
            emptyState("tray", "连接学习目录后显示材料", nil)
        } else if model.isLoadingIndex && model.filteredMaterials.isEmpty {
            ProgressView("正在读取索引")
                .font(.sn(11))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let knowledgeBaseID = model.currentDirectoryKnowledgeBaseID, !isSearching {
            directoryTree(knowledgeBaseID)
        } else if model.filteredMaterials.isEmpty {
            emptyState(emptyImage, isSearching ? "没有匹配的材料" : emptyTitle, emptyDetail)
        } else {
            materialList
        }
    }

    private func directoryTree(_ knowledgeBaseID: UUID) -> some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                rootRow(knowledgeBaseID)
                if model.isDirectoryExpanded(
                    path: "",
                    in: knowledgeBaseID
                ) {
                    DirectoryBranch(
                        model: model,
                        knowledgeBaseID: knowledgeBaseID,
                        parentPath: "",
                        depth: 1,
                        onDelete: requestDelete
                    )
                    if model.childFolders(
                        in: knowledgeBaseID,
                        parentPath: ""
                    ).isEmpty,
                       model.childMaterials(
                           in: knowledgeBaseID,
                           parentPath: ""
                       ).isEmpty {
                        emptyState(emptyImage, emptyTitle, emptyDetail)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .contextMenu {
            Button("新建文件夹", systemImage: "folder.badge.plus") {
                model.presentCreateFolderSheet(
                    in: knowledgeBaseID,
                    parentPath: model.currentDirectoryFolderPath
                )
            }
            Button("新建 Markdown 笔记", systemImage: "square.and.pencil") {
                model.presentCreateNoteSheet(
                    in: knowledgeBaseID,
                    folderPath: model.currentDirectoryFolderPath
                )
            }
            Button("导入材料…", systemImage: "square.and.arrow.down") {
                model.presentImportSheet(
                    in: knowledgeBaseID,
                    folderPath: model.currentDirectoryFolderPath
                )
            }
        }
    }

    private func rootRow(_ knowledgeBaseID: UUID) -> some View {
        let target = WorkspaceDropTarget.knowledgeBaseRoot(knowledgeBaseID)
        let isSelected = model.selectedCollection == .knowledgeBase(knowledgeBaseID)
        let isExpanded = model.isDirectoryExpanded(
            path: "",
            in: knowledgeBaseID
        )
        return HStack(spacing: 5) {
            Button {
                model.toggleDirectoryExpansion(
                    path: "",
                    in: knowledgeBaseID
                )
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起知识库" : "展开知识库")

            Button {
                Task {
                    await model.selectTreeKnowledgeBase(knowledgeBaseID)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 15)
                    Text("知识库根目录")
                        .font(.sn(11, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(model.materialCount(inKnowledgeBase: knowledgeBaseID))")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                }
                .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                .padding(.trailing, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        .modifier(
            WorkspaceDropHighlight(
                isTargeted: isRootTargeted,
                isAllowed: model.activeDragPayload.map {
                    model.canDrop($0, on: target)
                } ?? true
            )
        )
        .dropDestination(
            for: WorkspaceDragPayload.self,
            action: { payloads, _ in
                guard let payload = payloads.first,
                      model.canDrop(payload, on: target) else { return false }
                Task {
                    await model.drop(payload, on: target)
                    model.activeDragPayload = nil
                }
                return true
            },
            isTargeted: { isRootTargeted = $0 }
        )
        .contextMenu {
            Button("新建文件夹", systemImage: "folder.badge.plus") {
                model.presentCreateFolderSheet(
                    in: knowledgeBaseID,
                    parentPath: ""
                )
            }
            Button("新建 Markdown 笔记", systemImage: "square.and.pencil") {
                model.presentCreateNoteSheet(
                    in: knowledgeBaseID,
                    folderPath: ""
                )
            }
            Button("导入材料…", systemImage: "square.and.arrow.down") {
                model.presentImportSheet(
                    in: knowledgeBaseID,
                    folderPath: ""
                )
            }
        }
    }

    private var materialList: some View {
        List(selection: $model.selectedMaterialIDs) {
            ForEach(model.filteredMaterials) { material in
                MaterialRow(
                    model: model,
                    material: material,
                    isSelected: model.selectedMaterialIDs.contains(material.id),
                    knowledgeBaseName: model.knowledgeBases.first {
                        $0.id == material.knowledgeBaseID
                    }?.name,
                    searchHit: model.searchHits.first { $0.materialID == material.id }
                )
                .tag(material.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 48)
        .disabled(model.isLoadingIndex)
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.sn(10))
                .lineLimit(2)
            Spacer()
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

    private func emptyState(
        _ systemImage: String,
        _ title: String,
        _ detail: String?
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func revealSelectedFolder() {
        guard let knowledgeBaseID = model.selectedKnowledgeBaseID,
              let path = model.selectedFolderPath else {
            return
        }
        model.expandDirectoryAncestors(of: path, in: knowledgeBaseID)
    }

    private func requestDelete(_ folder: KnowledgeFolder) {
        deletionRequest = FolderDeletionRequest(folder: folder)
    }

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectionSummary: String {
        switch model.selectedMaterialIDs.count {
        case 0:
            "全部 \(model.filteredMaterials.count)"
        case 1:
            "已选择 1 篇"
        default:
            "已选择 \(model.selectedMaterialIDs.count) 篇"
        }
    }

    private var resultSummary: String {
        if isSearching {
            return "\(model.filteredMaterials.count) 个结果"
        }
        if model.currentDirectoryKnowledgeBaseID != nil {
            return "文件夹优先 · 按名称"
        }
        return "按名称"
    }

    private var emptyImage: String {
        if isSearching { return "magnifyingglass" }
        return switch model.selectedCollection {
        case .inbox: "tray"
        case .recycleBin: "trash"
        case .tag: "tag"
        default: "doc.text"
        }
    }

    private var emptyTitle: String {
        switch model.selectedCollection {
        case .inbox: "收件箱为空"
        case .recycleBin: "回收站为空"
        case .tag: "没有使用此标签的材料"
        default: "此位置暂无材料"
        }
    }

    private var emptyDetail: String? {
        switch model.selectedCollection {
        case .inbox:
            "可从工具栏把材料整理进知识库或文件夹。"
        case .recycleBin:
            "回收站材料会保留 30 天。"
        default:
            "可新建笔记、导入材料或进入上方子文件夹。"
        }
    }
}

private struct DirectoryBranch: View {
    @Bindable var model: WorkspaceModel
    let knowledgeBaseID: UUID
    let parentPath: String
    let depth: Int
    let onDelete: (KnowledgeFolder) -> Void

    var body: some View {
        ForEach(
            model.childFolders(
                in: knowledgeBaseID,
                parentPath: parentPath
            )
        ) { folder in
            FolderTreeRow(
                model: model,
                folder: folder,
                depth: depth,
                onDelete: onDelete
            )
        }
        ForEach(
            model.childMaterials(
                in: knowledgeBaseID,
                parentPath: parentPath
            )
        ) { material in
            CompactTreeMaterialRow(
                model: model,
                material: material,
                depth: depth
            )
        }
    }
}

private struct FolderTreeRow: View {
    @Bindable var model: WorkspaceModel
    let folder: KnowledgeFolder
    let depth: Int
    let onDelete: (KnowledgeFolder) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 1) {
            row
            if isExpanded {
                DirectoryBranch(
                    model: model,
                    knowledgeBaseID: folder.knowledgeBaseID,
                    parentPath: folder.path,
                    depth: depth + 1,
                    onDelete: onDelete
                )
            }
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    model.toggleDirectoryExpansion(
                        path: folder.path,
                        in: folder.knowledgeBaseID
                    )
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起 \(folder.name)" : "展开 \(folder.name)")

            Button {
                Task {
                    await model.selectTreeFolder(
                        knowledgeBaseID: folder.knowledgeBaseID,
                        path: folder.path
                    )
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                        .frame(width: 15)
                    Text(folder.name)
                        .font(.sn(11, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text("\(materialCount)")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                }
                .padding(.trailing, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 14 + 4)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        .modifier(
            WorkspaceDropHighlight(
                isTargeted: isTargeted,
                isAllowed: model.activeDragPayload.map {
                    model.canDrop($0, on: dropTarget)
                } ?? true
            )
        )
        .contextMenu {
            FolderMenuContent(model: model, folder: folder, onDelete: onDelete)
        }
        .onDrag {
            let payload = folderPayload
            model.activeDragPayload = payload
            return WorkspaceDragItemProvider.make(payload)
        }
        .dropDestination(
            for: WorkspaceDragPayload.self,
            action: { payloads, _ in
                guard let payload = payloads.first,
                      model.canDrop(payload, on: dropTarget) else {
                    return false
                }
                Task {
                    if await model.drop(payload, on: dropTarget) {
                        model.expandDirectoryAncestors(
                            of: folder.path,
                            in: folder.knowledgeBaseID
                        )
                    }
                    model.activeDragPayload = nil
                }
                return true
            },
            isTargeted: { isTargeted = $0 }
        )
        .onChange(of: isTargeted) {
            hoverTask?.cancel()
            guard isTargeted,
                  !isExpanded,
                  model.activeDragPayload.map({
                      model.canDrop($0, on: dropTarget)
                  }) == true else {
                return
            }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, isTargeted else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    model.expandDirectoryAncestors(
                        of: folder.path,
                        in: folder.knowledgeBaseID
                    )
                }
            }
        }
    }

    private var isExpanded: Bool {
        model.isDirectoryExpanded(
            path: folder.path,
            in: folder.knowledgeBaseID
        )
    }

    private var materialCount: Int {
        model.folderMaterialCount(
            knowledgeBaseID: folder.knowledgeBaseID,
            path: folder.path
        )
    }

    private var isSelected: Bool {
        model.selectedCollection == .folder(
            knowledgeBaseID: folder.knowledgeBaseID,
            path: folder.path
        )
    }

    private var folderPayload: WorkspaceDragPayload {
        WorkspaceDragPayload(
            kind: .folder,
            knowledgeBaseID: folder.knowledgeBaseID,
            folderPath: folder.path
        )
    }

    private var dropTarget: WorkspaceDropTarget {
        .folder(
            knowledgeBaseID: folder.knowledgeBaseID,
            path: folder.path
        )
    }
}

private struct FolderMenuContent: View {
    @Bindable var model: WorkspaceModel
    let folder: KnowledgeFolder
    let onDelete: (KnowledgeFolder) -> Void

    var body: some View {
        Button("新建子文件夹", systemImage: "folder.badge.plus") {
            model.presentCreateFolderSheet(
                in: folder.knowledgeBaseID,
                parentPath: folder.path
            )
        }
        Button("重命名", systemImage: "pencil") {
            model.renameRequest = .folder(folder)
        }
        Button("移动到…", systemImage: "arrow.right") {
            model.moveFolderRequest = WorkspaceMoveFolderRequest(folder: folder)
        }
        Divider()
        Button("新建 Markdown 笔记", systemImage: "square.and.pencil") {
            model.presentCreateNoteSheet(
                in: folder.knowledgeBaseID,
                folderPath: folder.path
            )
        }
        Button("导入材料", systemImage: "square.and.arrow.down") {
            model.presentImportSheet(
                in: folder.knowledgeBaseID,
                folderPath: folder.path
            )
        }
        Divider()
        Button("删除文件夹", systemImage: "trash", role: .destructive) {
            onDelete(folder)
        }
    }
}

private struct CompactTreeMaterialRow: View {
    @Bindable var model: WorkspaceModel
    let material: StudyMaterialSummary
    let depth: Int

    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: CGFloat(depth) * 14 + 16)
            Image(systemName: material.kind.systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                .frame(width: 14)
            Text(material.title)
                .font(.sn(11, weight: isReading ? .semibold : .regular))
                .foregroundStyle(SNColor.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !material.conflictCopies.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SNColor.orange)
                    .help("\(material.conflictCopies.count) 个冲突副本")
            }
            Image(systemName: "globe")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(
                    material.publishMapping == nil
                        ? SNColor.muted.opacity(0.6)
                        : SNColor.green
                )
                .help(
                    material.publishMapping == nil
                        ? "Web：未发布"
                        : "Web：已发布"
                )
        }
        .padding(.trailing, 8)
        .frame(height: 36)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
        .contentShape(Rectangle())
        .onTapGesture {
            let mode = selectionMode
            Task {
                await model.selectTreeMaterial(
                    material.id,
                    mode: mode
                )
            }
        }
        .help(materialHelp)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            materialMenu
        }
        .modifier(OptionalDraggable(model: model, payload: dragPayload))
    }

    private var isSelected: Bool {
        model.selectedMaterialIDs.contains(material.id)
    }

    private var isReading: Bool {
        model.readingMaterialID == material.id
    }

    private var selectionMode: WorkspaceTreeSelectionMode {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) {
            return .extendRange
        }
        if flags.contains(.command) {
            return .toggle
        }
        return .replace
    }

    private var materialHelp: String {
        let folder = material.folderPath.isEmpty
            ? "知识库根目录"
            : WorkspaceFormatting.folderPathDisplay(material.folderPath)
        let tags = material.tags.isEmpty
            ? "无标签"
            : material.tags.map { "#\($0)" }.joined(separator: " ")
        return [
            "\(folder) · \(material.kind.displayName)",
            "更新于 \(WorkspaceFormatting.updatedDate(material.updatedAt))",
            tags
        ].joined(separator: "\n")
    }

    private var dragPayload: WorkspaceDragPayload? {
        guard material.deletedAt == nil else {
            return nil
        }
        let visibleIDs = material.knowledgeBaseID.map {
            Set(model.visibleDirectoryMaterialIDs(in: $0))
        } ?? []
        let visibleSelection = model.selectedMaterialIDs
            .intersection(visibleIDs)
        let ids = isSelected && visibleSelection.count > 1
            ? visibleSelection
            : [material.id]
        return WorkspaceDragPayload(
            kind: .materials,
            knowledgeBaseID: material.knowledgeBaseID,
            materialIDs: Array(ids)
        )
    }

    @ViewBuilder
    private var materialMenu: some View {
        Button("打开", systemImage: "book") {
            Task { await model.selectMaterial(material.id) }
        }
        Button("移动到…", systemImage: "folder") {
            normalizeSelection()
            model.isShowingMoveMaterials = true
        }
        Button("编辑标签", systemImage: "tag") {
            normalizeSelection()
            model.isShowingEditTags = true
        }
        Divider()
        Button("移入回收站", systemImage: "trash", role: .destructive) {
            normalizeSelection()
            model.isConfirmingRecycle = true
        }
    }

    private func normalizeSelection() {
        if !model.selectedMaterialIDs.contains(material.id) {
            model.selectedMaterialIDs = [material.id]
        }
    }
}

private struct MaterialRow: View {
    @Bindable var model: WorkspaceModel
    let material: StudyMaterialSummary
    let isSelected: Bool
    let knowledgeBaseName: String?
    let searchHit: SearchHit?

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(SNColor.blueSoft)
                Image(systemName: material.deletedAt == nil ? material.kind.systemImage : "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SNColor.blue)
            }
            .frame(width: 22, height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(SNColor.blueLine, lineWidth: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(material.title)
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(1)
                Text(metadataLine)
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
                .padding(.leading, 42)
        }
        .help(searchHit?.snippet ?? tagLine)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("打开", systemImage: "book") {
                Task { await model.selectMaterial(material.id) }
            }
            Button("移动到…", systemImage: "folder") {
                normalizeSelection()
                model.isShowingMoveMaterials = true
            }
            Button("编辑标签", systemImage: "tag") {
                normalizeSelection()
                model.isShowingEditTags = true
            }
            Divider()
            Button("移入回收站", systemImage: "trash", role: .destructive) {
                normalizeSelection()
                model.isConfirmingRecycle = true
            }
        }
        .modifier(OptionalDraggable(model: model, payload: dragPayload))
    }

    private var metadataLine: String {
        if let deletedAt = material.deletedAt {
            return "删除于 \(WorkspaceFormatting.updatedDate(deletedAt)) · \(WorkspaceFormatting.recycleExpiryLabel(deletedAt: deletedAt))"
        }
        let folder = material.folderPath.isEmpty
            ? knowledgeBaseName ?? "收件箱"
            : WorkspaceFormatting.folderPathDisplay(material.folderPath)
        return "\(folder) · \(material.kind.displayName) · \(WorkspaceFormatting.updatedDate(material.updatedAt))"
    }

    private var tagLine: String {
        material.tags.isEmpty ? "未添加标签" : material.tags.map { "#\($0)" }.joined(separator: "  ")
    }

    private var dragPayload: WorkspaceDragPayload? {
        guard material.deletedAt == nil else {
            return nil
        }
        let ids = isSelected && !model.selectedMaterialIDs.isEmpty
            ? model.selectedMaterialIDs
            : [material.id]
        return WorkspaceDragPayload(
            kind: .materials,
            knowledgeBaseID: material.knowledgeBaseID,
            materialIDs: Array(ids)
        )
    }

    private func normalizeSelection() {
        if !model.selectedMaterialIDs.contains(material.id) {
            model.selectedMaterialIDs = [material.id]
        }
    }
}

private struct FolderDeletionRequest: Identifiable {
    let folder: KnowledgeFolder
    var id: String { folder.path }
}

private struct OptionalDraggable: ViewModifier {
    let model: WorkspaceModel
    let payload: WorkspaceDragPayload?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let payload {
            content.onDrag {
                model.activeDragPayload = payload
                return WorkspaceDragItemProvider.make(payload)
            }
        } else {
            content
        }
    }
}
