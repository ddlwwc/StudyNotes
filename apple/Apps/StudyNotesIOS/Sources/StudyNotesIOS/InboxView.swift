#if os(iOS)
import PhotosUI
import SwiftUI
import StudyNotesIOSCore

struct InboxView: View {
    @Bindable var model: IOSAppModel
    @State private var showingLinkComposer = false
    @State private var showingTextComposer = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    headerStatus
                    SectionTitle(
                        title: "快速收集",
                        detail: "写入 iCloud，回 Mac 统一整理"
                    )
                    quickActions
                    SectionTitle(
                        title: "等待整理",
                        detail: "\(model.inboxItems.count) 项"
                    )
                    if model.inboxItems.isEmpty {
                        ContentUnavailableView(
                            "收件箱为空",
                            systemImage: "tray",
                            description: Text("链接、图片和文本会先出现在这里。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(SNColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(model.inboxItems) { item in
                            InboxItemRow(item: item) {
                                Task { await model.retryInboxItem(item) }
                            } onDiscard: {
                                Task { await model.discardInboxItem(item) }
                            }
                        }
                    }
                    scopeNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(SNColor.page)
            .navigationTitle("收件箱")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.reloadAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新收件箱")
                }
            }
            .refreshable {
                await model.reloadAll()
            }
            .sheet(isPresented: $showingLinkComposer) {
                URLComposer { value in
                    await model.collectURL(value)
                }
            }
            .sheet(isPresented: $showingTextComposer) {
                TextComposer { value in
                    await model.collectText(value)
                }
            }
            .onChange(of: photoItem) {
                guard let photoItem else {
                    return
                }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self) {
                        await model.collectImage(
                            data: data,
                            title: "分享图片",
                            pathExtension: "jpg"
                        )
                    } else {
                        model.errorMessage = "无法读取所选图片。"
                    }
                    self.photoItem = nil
                }
            }
        }
    }

    private var headerStatus: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(model.isICloud ? SNColor.green : SNColor.amber)
                .frame(width: 7, height: 7)
            Text(model.isICloud ? "iCloud 收件箱 · 就绪" : "本地待同步收件箱")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(model.isICloud ? SNColor.green : SNColor.amberInk)
            Spacer()
            Text("\(model.inboxItems.count) 项")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(SNColor.primary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(SNColor.primarySoft)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(SNColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button {
                showingLinkComposer = true
            } label: {
                QuickCollectCard(
                    title: "链接",
                    detail: "抓取网页",
                    systemImage: "link"
                )
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                QuickCollectCard(
                    title: "图片",
                    detail: "保存截图",
                    systemImage: "photo"
                )
            }
            Button {
                showingTextComposer = true
            } label: {
                QuickCollectCard(
                    title: "文本",
                    detail: "粘贴片段",
                    systemImage: "text.alignleft"
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var scopeNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(SNColor.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("收件箱只负责轻量收集")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Text("可在资料库移动材料或整理文件夹；标签编辑仍在 Mac 完成。")
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

private struct QuickCollectCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SNColor.primary)
                    .frame(width: 30, height: 30)
                    .background(SNColor.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SNColor.primary)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SNColor.ink)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(SNColor.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(SNColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
    }
}

private struct InboxItemRow: View {
    let item: InboxItem
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(iconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(1)
                Text("\(item.kind.label) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            status
        }
        .padding(12)
        .background(SNColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(SNColor.border, lineWidth: 1)
        }
        .contextMenu {
            if case .failed = item.status {
                Button("重试", action: onRetry)
                Button("丢弃本地草稿", role: .destructive, action: onDiscard)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .collected:
            StatusPill(
                text: "已同步",
                color: SNColor.green,
                background: SNColor.greenSoft,
                systemImage: "checkmark.circle"
            )
        case .pending:
            StatusPill(
                text: "待同步",
                color: SNColor.amberInk,
                background: SNColor.amberSoft,
                systemImage: "clock"
            )
        case .failed:
            Button("重试", action: onRetry)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(SNColor.amberInk)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(SNColor.amberSoft)
                .clipShape(Capsule())
        }
    }

    private var icon: String {
        switch item.kind {
        case .url:
            "link"
        case .image:
            "photo"
        case .text:
            "text.alignleft"
        }
    }

    private var iconColor: Color {
        item.kind == .image ? SNColor.green : SNColor.primary
    }

    private var iconBackground: Color {
        item.kind == .image ? SNColor.greenSoft : SNColor.primarySoft
    }
}

private struct URLComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    let onSubmit: (String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("网址") {
                    TextField("https://", text: $value)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("收集链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收集") {
                        let submitted = value
                        dismiss()
                        Task { await onSubmit(submitted) }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct TextComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    let onSubmit: (String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("文本片段") {
                    TextEditor(text: $value)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("收集文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收集") {
                        let submitted = value
                        dismiss()
                        Task { await onSubmit(submitted) }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
