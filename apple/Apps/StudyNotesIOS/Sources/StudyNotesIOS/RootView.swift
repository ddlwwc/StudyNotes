#if os(iOS)
import SwiftUI
import StudyNotesIOSCore

struct RootView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            LibraryView(model: model)
                .tabItem {
                    Label("资料库", systemImage: "books.vertical")
                }
                .tag(IOSAppModel.Tab.library)

            InboxView(model: model)
                .tabItem {
                    Label("收件箱", systemImage: "tray")
                }
                .tag(IOSAppModel.Tab.inbox)

            SearchView(model: model)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(IOSAppModel.Tab.search)

            ReviewView()
                .tabItem {
                    Label("复习", systemImage: "arrow.clockwise")
                }
                .tag(IOSAppModel.Tab.review)
        }
        .tint(SNColor.primary)
        .onOpenURL { url in
            Task {
                model.selectedTab = .inbox
                await model.handleIncomingURL(url)
            }
        }
        .sheet(isPresented: $model.showingProviderSettings) {
            AIProviderSettingsView(model: model)
        }
        .overlay(alignment: .top) {
            if let notice = model.noticeMessage {
                ToastBanner(
                    text: notice,
                    color: SNColor.green,
                    background: SNColor.greenSoft
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2))
                        model.noticeMessage = nil
                    }
            }
        }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .animation(.easeInOut(duration: 0.2), value: model.noticeMessage)
    }
}

private struct ToastBanner: View {
    let text: String
    let color: Color
    let background: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(background)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }
}

private struct ReviewView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(SNColor.muted)
                Text("暂无到期复习")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SNColor.text)
                Text("复习项会按本地计划出现在这里。")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SNColor.nav)
            .navigationTitle("复习")
        }
    }
}
#endif
