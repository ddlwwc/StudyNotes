import SwiftUI
import StudyCore

public struct NoteListView: View {
    @Bindable var model: AppModel
    @State private var selection: Note.ID?
    @State private var isCreating = false
    @State private var newTitle = ""
    @State private var newTags = ""
    @State private var searchText = ""

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            Group {
                if model.hasVault {
                    List(selection: $selection) {
                        ForEach(groupedNotes, id: \.name) { group in
                            Section {
                                ForEach(group.notes) { note in
                                    row(for: note)
                                        .tag(note.id)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: group.icon)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(group.name)
                                    Spacer()
                                    Text("\(group.notes.count)")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "搜索笔记")
                } else {
                    ContentUnavailableView {
                        Label("还没有选择笔记目录", systemImage: "folder.badge.plus")
                    } description: {
                        Text("到「设置」里选一个文件夹，笔记会以 Markdown 文件存放其中。")
                    }
                }
            }
            .navigationTitle("学习笔记")
            .toolbar {
                ToolbarItem {
                    Button {
                        isCreating = true
                    } label: {
                        Label("新建", systemImage: "square.and.pencil")
                    }
                    .disabled(!model.hasVault)
                }
            }
            .alert("新建笔记", isPresented: $isCreating) {
                TextField("标题", text: $newTitle)
                TextField("分类（可选，多个用逗号分隔）", text: $newTags)
                Button("取消", role: .cancel) {
                    newTitle = ""
                    newTags = ""
                }
                Button("创建") {
                    createNote()
                }
            }
        } detail: {
            if let selection, let note = model.notes.notes.first(where: { $0.id == selection }) {
                NoteEditorView(model: model, note: note)
            } else {
                ContentUnavailableView("选择一篇笔记", systemImage: "doc.text")
            }
        }
    }

    private struct NoteGroup: Identifiable {
        let name: String
        let icon: String
        var notes: [Note]
        var id: String { name }
    }

    private var groupedNotes: [NoteGroup] {
        let filtered: [Note]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = model.notes.notes
        } else {
            let key = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            filtered = model.notes.notes.filter { note in
                note.title.lowercased().contains(key)
                    || note.tags.joined(separator: " ").lowercased().contains(key)
                    || note.body.lowercased().contains(key)
            }
        }

        let buckets = Dictionary(grouping: filtered) { note in
            note.tags.first ?? "未分类"
        }

        return buckets
            .map { name, notes in
                NoteGroup(
                    name: name,
                    icon: name == "未分类" ? "tray" : "folder",
                    notes: notes.sorted {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                if lhs.name == "未分类" { return false }
                if rhs.name == "未分类" { return true }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func row(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .lineLimit(1)
            HStack(spacing: 6) {
                if !note.cards.isEmpty {
                    Text("\(note.cards.count) 张卡片")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(note.tags.dropFirst(), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func createNote() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = newTags
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        newTitle = ""
        newTags = ""
        do {
            let note = try model.notes.create(title: title.isEmpty ? "未命名" : title, tags: tags)
            selection = note.id
        } catch {
            model.startupError = error.localizedDescription
        }
    }
}
