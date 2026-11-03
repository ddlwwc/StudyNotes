import SwiftUI

public struct AppShell: View {
    @Bindable private var model: WorkspaceModel
    private let restoresWorkspace: Bool

    public init(model: WorkspaceModel, restoresWorkspace: Bool = true) {
        self.model = model
        self.restoresWorkspace = restoresWorkspace
    }

    public var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(model: model)
                .frame(width: SNMetric.sidebarWidth)

            MaterialListPane(model: model)
                .frame(width: SNMetric.materialListWidth)

            ReaderWorkspace(model: model)
                .frame(minWidth: 460, maxWidth: .infinity)
        }
        .frame(
            minWidth: SNMetric.minimumWindowWidth,
            minHeight: SNMetric.minimumWindowHeight
        )
        .background(SNColor.white)
        .preferredColorScheme(.light)
        .toolbar {
            WorkspaceToolbar(model: model)
        }
        .sheet(isPresented: $model.isShowingCreateKnowledgeBase) {
            CreateKnowledgeBaseSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingCreateNote) {
            CreateNoteSheet(model: model)
        }
        .sheet(item: $model.createFolderRequest) { request in
            CreateFolderSheet(model: model, request: request)
        }
        .sheet(item: $model.renameRequest) { target in
            RenameWorkspaceItemSheet(model: model, target: target)
        }
        .sheet(item: $model.moveFolderRequest) { request in
            MoveFolderSheet(model: model, request: request)
        }
        .sheet(isPresented: $model.isShowingMoveMaterials) {
            MoveMaterialsSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingEditTags) {
            EditTagsSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingImport) {
            ImportMaterialSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingWebImport) {
            WebArticleImportSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingEditReaderCopy) {
            EditReaderCopySheet(model: model)
        }
        .sheet(isPresented: $model.isShowingVersions) {
            VersionHistorySheet(model: model)
        }
        .sheet(isPresented: $model.isShowingLinkMaterials) {
            LinkMaterialsSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingAIConfiguration) {
            AIConfigurationSheet(model: model)
        }
        .sheet(item: $model.pendingAIContext) { preview in
            AIContextConfirmationSheet(model: model, preview: preview)
        }
        .sheet(item: $model.annotationDraftRequest) { request in
            AnnotationEditorSheet(model: model, request: request)
        }
        .sheet(isPresented: $model.isShowingPublishPreview) {
            PublishPreviewSheet(model: model)
        }
        .confirmationDialog(
            "将 \(model.selectedMaterialIDs.count) 篇材料移入回收站？",
            isPresented: $model.isConfirmingRecycle,
            titleVisibility: .visible
        ) {
            Button("移入回收站", role: .destructive) {
                Task {
                    await model.moveSelectedMaterialsToRecycleBin()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("材料会保留 30 天，并可在回收站中恢复到原位置。")
        }
        .confirmationDialog(
            "永久清理 \(model.expiredRecycleCount) 篇过期材料？",
            isPresented: $model.isConfirmingPurgeExpired,
            titleVisibility: .visible
        ) {
            Button("永久清理", role: .destructive) {
                Task {
                    await model.purgeExpiredRecycleBin()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清理超过 30 天的材料，此操作无法撤销。")
        }
        .alert("无法完成操作", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .task {
            if restoresWorkspace {
                await model.restoreLastWorkspace()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.isConnected, !urls.isEmpty else {
                return false
            }
            Task {
                _ = await model.importFiles(
                    urls,
                    knowledgeBaseID: model.defaultImportKnowledgeBaseID,
                    folderPath: model.defaultImportFolderPath,
                    tags: []
                )
            }
            return true
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissError()
                }
            }
        )
    }
}

private struct ReaderWorkspace: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            ReaderPane(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isStudyPanelVisible {
                StudyPanel(model: model)
                    .frame(width: SNMetric.studyPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}
