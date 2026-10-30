import SwiftUI
import StudyCore
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var draftKey = ""
    @State private var draftModel = ""
    @State private var draftBaseURL = ""
    @State private var status: String?
    @State private var isPickingVault = false
    @State private var isPickingImport = false
    @State private var importSummary: String?
    @State private var isImporting = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case key
        case model
        case baseURL
    }

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            vaultSection

            Section {
                SecureField("API Key", text: $draftKey)
                    .textContentType(.password)
                    .focused($focusedField, equals: .key)
                TextField("模型", text: $draftModel)
                    .focused($focusedField, equals: .model)
                TextField("Base URL", text: $draftBaseURL)
                    .focused($focusedField, equals: .baseURL)
            } header: {
                Text("DeepSeek")
            } footer: {
                Text("API Key 保存在系统钥匙串里，不写入笔记目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    focusedField = nil
                    save()
                } label: {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let status {
                Section {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedField = nil
            }
        )
        .task {
            draftKey = model.settings.apiKey
            draftModel = model.settings.model
            draftBaseURL = model.settings.baseURLString
        }
        .fileImporter(
            isPresented: $isPickingVault,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.selectVault(url)
                status = model.startupError ?? "已选择笔记目录"
            case .failure(let error):
                status = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isPickingImport,
            allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                performImport(urls)
            case .failure(let error):
                importSummary = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var vaultSection: some View {
        Section {
            if let url = model.vaultURL {
                LabeledContent("当前目录") {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                }
                Button("更换目录") {
                    isPickingVault = true
                }
                Button {
                    isPickingImport = true
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Label("导入 Markdown 文档", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)

                if let importSummary {
                    Text(importSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("还没有选择笔记目录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    isPickingVault = true
                } label: {
                    Label("选择文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = model.startupError, model.vaultURL == nil {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("笔记目录")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("建议选 iCloud Drive 下的文件夹，Mac 与 iPhone 会自动同步。")
                Text("导入会把选中的 .md 文件复制到笔记目录；同名文件会被跳过，不会覆盖。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func performImport(_ urls: [URL]) {
        isImporting = true
        importSummary = nil
        defer { isImporting = false }
        let outcome = model.notes.importNotes(urls: urls)
        importSummary = outcome.summary
        if !outcome.failed.isEmpty {
            let detail = outcome.failed
                .prefix(3)
                .map { "\($0.name)：\($0.reason)" }
                .joined(separator: "\n")
            importSummary = "\(outcome.summary)\n\(detail)"
        }
    }

    private func save() {
        model.settings.apiKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        model.settings.model = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        model.settings.baseURLString = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.settings.save()
            status = "已保存"
        } catch {
            status = error.localizedDescription
        }
    }
}
