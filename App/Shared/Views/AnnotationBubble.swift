import SwiftUI
import StudyCore

struct AnnotationBubble: View {
    let annotation: Annotation
    let anchorText: String
    let onAddComment: (String) -> Void
    let onAddReply: (String, String) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var draft = ""
    @State private var replyTarget: Comment?
    @State private var replyDraft = ""
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(anchorText)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    if annotation.comments.isEmpty {
                        Text("还没有评论，在下面写第一条")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(annotation.comments.enumerated()), id: \.element.id) { index, comment in
                            commentRow(comment, floor: index + 1, depth: 0)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 260)

            Divider()
            composer
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("评论")
                .font(.caption.weight(.semibold))
            if annotation.commentCount > 0 {
                Text("\(annotation.commentCount) 层")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(spacing: 6) {
            TextField("写评论…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.callout)
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                onAddComment(text)
                draft = ""
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func commentRow(_ comment: Comment, floor: Int, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if depth == 0 {
                        Text("\(floor) 楼")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        replyTarget = comment
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }

                Text(comment.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(comment.replies) { reply in
                    HStack(alignment: .top, spacing: 6) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 2)
                        commentRow(reply, floor: floor, depth: depth + 1)
                    }
                    .padding(.leading, 6)
                    .padding(.top, 2)
                }

                if replyTarget?.id == comment.id {
                    replyComposer(to: comment)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        )
    }

    private func replyComposer(to target: Comment) -> some View {
        HStack(spacing: 6) {
            TextField("回复…", text: $replyDraft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.caption)
            Button {
                let text = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                onAddReply(text, target.id)
                replyDraft = ""
                replyTarget = nil
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button {
                replyDraft = ""
                replyTarget = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
