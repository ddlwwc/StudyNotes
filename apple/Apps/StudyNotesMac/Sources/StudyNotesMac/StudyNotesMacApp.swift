import StudyNotesMacUI
import SwiftUI

@main
@MainActor
struct StudyNotesMacApp: App {
    @State private var model: WorkspaceModel

    init() {
        _model = State(initialValue: WorkspaceModel())
    }

    var body: some Scene {
        WindowGroup("StudyNotes") {
            AppShell(model: model)
        }
        .defaultSize(width: 1_440, height: 1_024)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") {
                    model.presentCreateNoteSheet()
                }
                .keyboardShortcut("n")
                .disabled(!model.canCreateNote)

                Button("新建知识库") {
                    model.presentCreateKnowledgeBaseSheet()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.isConnected)
            }

            CommandMenu("工作区") {
                Button("导入材料…") {
                    model.presentImportSheet()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!model.isConnected)

                Button("导入网页文章…") {
                    model.presentImportSheet(webArticle: true)
                }
                .disabled(!model.isConnected)

                Divider()

                Button("选择学习目录…") {
                    Task {
                        await model.chooseWorkspace()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("重新加载索引") {
                    Task {
                        await model.reloadIndex()
                    }
                }
                .keyboardShortcut("r")
                .disabled(!model.isConnected || model.isLoadingIndex)

                Divider()

                Button("AI 供应商设置…") {
                    model.isShowingAIConfiguration = true
                }

                Button("发布预览…") {
                    model.preparePublishPreview()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.canPreviewPublish)
            }
        }
    }
}
