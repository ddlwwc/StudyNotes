import SwiftUI
import StudyCore

public struct VaultPickerView: View {
    @Bindable var model: AppModel
    @State private var isPicking = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("选择笔记目录")
                    .font(.title2.weight(.semibold))
                Text("这是笔记文件的存放位置。建议选 iCloud Drive 下的一个文件夹，Mac 与 iPhone 会自动同步。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                isPicking = true
            } label: {
                Label("选择文件夹", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = model.startupError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.selectVault(url)
                }
            case .failure(let error):
                model.startupError = error.localizedDescription
            }
        }
    }
}
