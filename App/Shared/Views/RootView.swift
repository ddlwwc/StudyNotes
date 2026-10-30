import SwiftUI
import StudyCore

public struct RootView: View {
    @Bindable var model: AppModel
    @State private var tab: Tab = .notes

    public init(model: AppModel) {
        self.model = model
    }

    public enum Tab: Hashable {
        case notes
        case review
        case scenario
        case settings
    }

    public var body: some View {
        TabView(selection: $tab) {
            NoteListView(model: model)
                .tabItem { Label("笔记", systemImage: "doc.text") }
                .tag(Tab.notes)

            NavigationStack {
                ReviewView(model: model)
            }
            .tabItem { Label("复习", systemImage: "rectangle.stack") }
            .tag(Tab.review)

            NavigationStack {
                ScenarioView(model: model)
            }
            .tabItem { Label("场景", systemImage: "bubble.left.and.bubble.right") }
            .tag(Tab.scenario)

            NavigationStack {
                SettingsView(model: model)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .task {
            if model.hasVault == false {
                model.restoreVault()
            }
        }
    }
}
