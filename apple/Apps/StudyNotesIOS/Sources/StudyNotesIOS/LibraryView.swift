#if os(iOS)
import SwiftUI
import StudyNotesIOSCore

struct LibraryView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    syncCard

                    if !model.snapshot.materials.isEmpty {
                        recentSection
                    }

                    SectionTitle(
                        title: "知识库",
                        detail: "\(model.snapshot.knowledgeBases.count) 个"
                    )

                    if model.snapshot.knowledgeBases.isEmpty {
                        emptyLibrary
                    } else {
                        ForEach(model.snapshot.knowledgeBases) { knowledgeBase in
                            NavigationLink {
                                KnowledgeBaseView(
                                    model: model,
                                    knowledgeBase: knowledgeBase
                                )
                            } label: {
                                KnowledgeBaseRow(
                                    knowledgeBase: knowledgeBase,
                                    materials: model.snapshot.materials.filter {
                                        $0.manifest.knowledgeBaseID == knowledgeBase.id
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    storageCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(SNColor.page)
            .navigationTitle("资料库")
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
            .refreshable {
                await model.reloadAll()
            }
            .navigationDestination(item: $model.readerRoute) { route in
                MaterialDestinationView(
                    model: model,
                    materialID: route.id
                )
            }
        }
    }

    private var syncCard: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isICloud ? "icloud.fill" : "iphone")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.isICloud ? SNColor.green : SNColor.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.rootState.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Text(
                    model.isICloud
                        ? "目录与元数据已同步，正文按需下载"
                        : "当前使用本地演练目录"
                )
                .font(.system(size: 10))
                .foregroundStyle(SNColor.muted)
            }
            Spacer()
            if !model.isICloud {
                Button("连接 iCloud") {
                    Task { await model.retryICloud() }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(SNColor.primary)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "最近阅读", detail: "最近更新")
            ForEach(Array(model.snapshot.materials.prefix(3))) { material in
                NavigationLink {
                    MaterialDestinationView(
                        model: model,
                        materialID: material.id
                    )
                } label: {
                    RecentMaterialCard(material: material)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(SNColor.muted)
            Text("还没有知识库")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SNColor.text)
            Text("在 Mac 创建知识库后，这里会显示目录元数据。")
                .font(.system(size: 10.5))
                .foregroundStyle(SNColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
    }

    private var storageCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 15))
                .foregroundStyle(SNColor.text)
            VStack(alignment: .leading, spacing: 4) {
                Text("离线保存")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Text(
                    "\(model.snapshot.materials.count(where: { $0.accessState == .offline })) 份材料已保存到本机"
                )
                .font(.system(size: 10))
                .foregroundStyle(SNColor.muted)
            }
            Spacer()
        }
        .padding(12)
        .background(SNColor.nav)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct KnowledgeBaseRow: View {
    let knowledgeBase: KnowledgeBaseSummary
    let materials: [LibraryMaterial]

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "folder.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SNColor.primary)
                .frame(width: 34, height: 34)
                .background(SNColor.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(knowledgeBase.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(1)
                Text("\(materials.count) 份材料 · 正文按需下载")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SNColor.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
    }
}

private struct RecentMaterialCard: View {
    let material: LibraryMaterial

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kindIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SNColor.primary)
                .frame(width: 62, height: 70)
                .background(SNColor.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(material.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    AccessStatePill(state: material.accessState)
                }
                Text("\(material.kind.label) · \(material.knowledgeBaseName)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
                if !material.tags.isEmpty {
                    Text(material.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 9))
                        .foregroundStyle(SNColor.primary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 94)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
    }

    private var kindIcon: String {
        switch material.kind {
        case .image:
            "photo"
        case .pdf:
            "doc.richtext"
        case .note:
            "note.text"
        default:
            "book.closed"
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
               material.accessState == .downloaded || material.accessState == .offline {
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
                        await prepare()
                    }
            }
        }
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

    private func prepare() async {
        guard !isPreparing else {
            return
        }
        isPreparing = true
        loadError = nil
        await model.download(materialID: materialID)
        isPreparing = false
        if let material = model.material(id: materialID),
           material.accessState == .metadataOnly || model.errorMessage != nil {
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

struct KnowledgeBaseView: View {
    @Bindable var model: IOSAppModel
    let knowledgeBase: KnowledgeBaseSummary

    private var materials: [LibraryMaterial] {
        model.snapshot.materials.filter {
            $0.manifest.knowledgeBaseID == knowledgeBase.id
        }
    }

    private var folders: [FolderNode] {
        LibraryTreeBuilder.folders(
            for: knowledgeBase.id,
            in: model.snapshot.materials
        )
    }

    private var rootMaterials: [LibraryMaterial] {
        materials.filter { $0.folderPath.isEmpty }
    }

    var body: some View {
        List {
            if !folders.isEmpty {
                Section("文件夹") {
                    ForEach(folders) { folder in
                        NavigationLink {
                            FolderView(
                                model: model,
                                knowledgeBase: knowledgeBase,
                                folder: folder
                            )
                        } label: {
                            Label {
                                HStack {
                                    Text(folder.name)
                                    Spacer()
                                    Text("\(folder.materialCount)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(SNColor.muted)
                                }
                            } icon: {
                                Image(systemName: "folder")
                                    .foregroundStyle(SNColor.primary)
                            }
                        }
                    }
                }
            }

            Section("材料") {
                if rootMaterials.isEmpty && folders.isEmpty {
                    ContentUnavailableView(
                        "没有学习材料",
                        systemImage: "books.vertical",
                        description: Text("此知识库的目录元数据为空。")
                    )
                } else {
                    ForEach(rootMaterials) { material in
                        NavigationLink {
                            MaterialDestinationView(
                                model: model,
                                materialID: material.id
                            )
                        } label: {
                            MaterialListRow(material: material)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(knowledgeBase.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct FolderView: View {
    @Bindable var model: IOSAppModel
    let knowledgeBase: KnowledgeBaseSummary
    let folder: FolderNode

    private var materials: [LibraryMaterial] {
        model.snapshot.materials.filter {
            $0.manifest.knowledgeBaseID == knowledgeBase.id
                && $0.folderPath == folder.path
        }
    }

    var body: some View {
        List {
            if !folder.children.isEmpty {
                Section("子文件夹") {
                    ForEach(folder.children) { child in
                        NavigationLink {
                            FolderView(
                                model: model,
                                knowledgeBase: knowledgeBase,
                                folder: child
                            )
                        } label: {
                            Label {
                                HStack {
                                    Text(child.name)
                                    Spacer()
                                    Text("\(child.materialCount)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(SNColor.muted)
                                }
                            } icon: {
                                Image(systemName: "folder")
                                    .foregroundStyle(SNColor.primary)
                            }
                        }
                    }
                }
            }
            Section("材料") {
                ForEach(materials) { material in
                    NavigationLink {
                        MaterialDestinationView(
                            model: model,
                            materialID: material.id
                        )
                    } label: {
                        MaterialListRow(material: material)
                    }
                }
            }
        }
        .navigationTitle(folder.name)
    }
}

private struct MaterialListRow: View {
    let material: LibraryMaterial

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: material.kind == .image ? "photo" : "doc.text")
                .foregroundStyle(SNColor.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(material.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text("\(material.kind.label) · \(material.tags.map { "#\($0)" }.joined(separator: " "))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            AccessStatePill(state: material.accessState)
        }
        .padding(.vertical, 3)
    }
}
#endif
