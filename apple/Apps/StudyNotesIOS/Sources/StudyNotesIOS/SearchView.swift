#if os(iOS)
import SwiftUI
import StudyNotesIOSCore

struct SearchView: View {
    @Bindable var model: IOSAppModel
    @FocusState private var isSearchFocused: Bool

    private var groupedHits: [(SearchHit.Kind, [SearchHit])] {
        let order: [SearchHit.Kind] = [.metadata, .content, .annotation, .ai]
        return order.compactMap { kind in
            let hits = model.searchHits.filter { $0.kind == kind }
            return hits.isEmpty ? nil : (kind, hits)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                Divider()
                results
            }
            .background(SNColor.page)
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showingProviderSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("AI 设置")
                }
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SNColor.muted)
                TextField("搜索材料、正文、标注与 AI 结果", text: $model.searchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: model.searchText) {
                        model.scheduleSearch()
                    }
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                        model.scheduleSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SNColor.muted)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(SNColor.nav)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                StatusPill(
                    text: model.searchScope.metadataLabel,
                    color: SNColor.text,
                    background: SNColor.nav,
                    systemImage: "tag"
                )
                StatusPill(
                    text: "全文 \(model.searchScope.fullTextCount) 份",
                    color: SNColor.primary,
                    background: SNColor.primarySoft,
                    systemImage: "doc.text.magnifyingglass"
                )
            }
            Text(model.searchScope.fullTextLabel)
                .font(.system(size: 9.5))
                .foregroundStyle(SNColor.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SNColor.surface)
    }

    @ViewBuilder
    private var results: some View {
        if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "查找学习材料",
                systemImage: "text.page.badge.magnifyingglass",
                description: Text("未下载材料的正文不会进入全文搜索。")
            )
            .frame(maxHeight: .infinity)
        } else if groupedHits.isEmpty {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(SNColor.muted)
                    Text("没有匹配结果")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SNColor.text)
                    Text("当前只搜索已下载或已离线保存材料的正文、标注和 AI 结果。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SNColor.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(groupedHits, id: \.0) { kind, hits in
                    Section(kind.label) {
                        ForEach(hits) { hit in
                            NavigationLink {
                                MaterialDestinationView(
                                    model: model,
                                    materialID: hit.materialID
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(hit.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(SNColor.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        SearchKindPill(kind: hit.kind)
                                    }
                                    Text(hit.snippet)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(SNColor.text)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct SearchKindPill: View {
    let kind: SearchHit.Kind

    var body: some View {
        let (color, background): (Color, Color) = {
            switch kind {
            case .metadata:
                (SNColor.text, SNColor.nav)
            case .content:
                (SNColor.primary, SNColor.primarySoft)
            case .annotation:
                (SNColor.amberInk, SNColor.amberSoft)
            case .ai:
                (Color(hex: 0x6E4B9E), Color(hex: 0xF4EFFA))
            }
        }()
        Text(kind.label)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(background)
            .clipShape(Capsule())
    }
}
#endif
