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
            StudyNotesCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
        .defaultSize(width: 920, height: 700)
    }
}

private struct StudyNotesCommands: Commands {
    let model: WorkspaceModel
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
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

        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                model.settingsPage = .workspace
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
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

            Button("学习目录设置…") {
                model.settingsPage = .workspace
                openSettings()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("重新加载索引") {
                Task { await model.reloadIndex() }
            }
            .keyboardShortcut("r")
            .disabled(!model.isConnected || model.isLoadingIndex)

            Divider()

            Button(model.isLibraryPaneVisible ? "隐藏知识库栏" : "显示知识库栏") {
                model.togglePane(.library)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button(model.isMaterialPaneVisible ? "隐藏材料目录栏" : "显示材料目录栏") {
                model.togglePane(.materials)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Button(model.isStudyPanelVisible ? "隐藏研读层" : "显示研读层") {
                model.togglePane(.study)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Button("AI 配置…") {
                model.settingsPage = .ai
                openSettings()
            }

            Button("发布预览…") {
                model.preparePublishPreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!model.canPreviewPublish)
        }
    }
}
