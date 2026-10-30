import SwiftUI
import StudyCore

public struct ReviewView: View {
    @Bindable var model: AppModel

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var answer = ""
    @State private var revealed = false
    @State private var isGrading = false
    @State private var feedback: String?
    @State private var message: String?

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            if queue.isEmpty {
                emptyState
            } else if currentCard == nil {
                finishedState
            } else {
                reviewBody
            }
        }
        .navigationTitle("复习")
        .toolbar {
            ToolbarItem {
                Button {
                    startSession()
                } label: {
                    Label("开始复习", systemImage: "play.circle")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有待复习的卡片", systemImage: "checkmark.circle")
        } description: {
            Text("点「开始复习」把新卡片加进来，或者先写一些笔记。")
        } actions: {
            Button("开始复习") { startSession() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var finishedState: some View {
        ContentUnavailableView {
            Label("这一轮完成了", systemImage: "flag.checkered")
        } description: {
            Text("复习了 \(queue.count) 张卡片")
        } actions: {
            Button("再来一轮") { startSession() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var reviewBody: some View {
        Group {
            if let card = currentCard {
                cardBody(card)
            } else {
                emptyState
            }
        }
    }

    private var currentCard: Card? {
        guard index >= 0, index < queue.count else { return nil }
        return queue[index]
    }

    private func cardBody(_ card: Card) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("\(index + 1) / \(queue.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if model.reviews.isNew(card) {
                        Text("新卡")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                }

                Text(card.question)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("你的回答")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $answer)
                        .font(.body)
                        .frame(minHeight: 120)
                        .padding(6)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }

                if revealed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("参考答案")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.answer)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let feedback, !feedback.isEmpty {
                        Text(feedback)
                            .font(.callout)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    gradeButtons(for: card)
                } else {
                    Button {
                        reveal(card)
                    } label: {
                        if isGrading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("判分中…")
                            }
                        } else {
                            Text("提交并评分")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGrading || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("显示答案（自己评）") {
                        revealed = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func gradeButtons(for card: Card) -> some View {
        HStack(spacing: 10) {
            ForEach(Grade.allCases, id: \.self) { grade in
                Button(label(for: grade)) {
                    apply(grade, to: card)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func label(for grade: Grade) -> String {
        switch grade {
        case .again: return "重来"
        case .hard: return "模糊"
        case .good: return "记得"
        case .easy: return "太简单"
        }
    }

    private func startSession() {
        let due = model.reviews.dueCards(from: model.notes.allCards)
        let fresh = Array(model.reviews.newCards(from: model.notes.allCards).prefix(20))
        var seen = Set<String>()
        queue = (due + fresh).filter { seen.insert($0.id).inserted }
        index = 0
        resetCardState()
        if queue.isEmpty {
            message = nil
        }
    }

    private func resetCardState() {
        answer = ""
        revealed = false
        feedback = nil
        message = nil
    }

    private func reveal(_ card: Card) {
        guard let client = model.client else {
            revealed = true
            return
        }
        isGrading = true
        let currentAnswer = answer
        Task {
            do {
                let result = try await client.grade(
                    question: card.question,
                    referenceAnswer: card.answer,
                    learnerAnswer: currentAnswer
                )
                feedback = result.feedback
                revealed = true
                try record(card, grade: result.grade)
                advance()
            } catch {
                message = error.localizedDescription
                revealed = true
            }
            isGrading = false
        }
    }

    private func apply(_ grade: Grade, to card: Card) {
        do {
            try record(card, grade: grade)
            advance()
        } catch {
            message = error.localizedDescription
        }
    }

    private func record(_ card: Card, grade: Grade) throws {
        try model.reviews.record(card: card, grade: grade)
    }

    private func advance() {
        index = min(index + 1, queue.count)
        resetCardState()
    }
}
