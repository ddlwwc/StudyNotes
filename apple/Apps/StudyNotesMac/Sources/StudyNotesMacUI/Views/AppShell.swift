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
