import SwiftUI
import StudyCore

public struct ScenarioView: View {
    @Bindable var model: AppModel

    @State private var runtime: ScenarioRuntime?
    @State private var selected: Scenario = BuiltinScenarios.teacher
    @State private var draft = ""
    @State private var useVoice = false
    @State private var transcriber = SpeechTranscriberService()
    @State private var savedBanner: String?

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            channelBar
            Divider()
            conversation
            Divider()
            composer
        }
        .navigationTitle("场景")
        .task {
            if runtime == nil {
                runtime = ScenarioRuntime(scenario: selected, runner: model.client)
                await runtime?.start()
            }
        }
        .onChange(of: selected) { _, newValue in
            runtime = ScenarioRuntime(scenario: newValue, runner: model.client)
            Task { await runtime?.start() }
        }
    }

    private var channelBar: some View {
        HStack(spacing: 16) {
            Picker("场景", selection: $selected) {
                ForEach(BuiltinScenarios.all) { scenario in
                    Text(scenario.name).tag(scenario as Scenario)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer()

            Toggle(isOn: $useVoice) {
                Label("语音", systemImage: "waveform")
            }
            .toggleStyle(.switch)

            Button {
                saveSession()
            } label: {
                Label("保存记录", systemImage: "square.and.arrow.down")
            }
            .disabled(runtime?.session.turns.isEmpty ?? true)

            if let savedBanner {
                Text(savedBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var conversation: some View {
        if let runtime {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(runtime.session.turns) { turn in
                            turnRow(turn)
                                .id(turn.id)
                        }
                        if runtime.isThinking {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("思考中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .id("thinking")
                        }
                        if let error = runtime.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: runtime.session.turns.count) { _, _ in
                    if let last = runtime.session.turns.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func turnRow(_ turn: Turn) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: turn.speaker == .learner ? "person.fill" : "graduationcap.fill")
                .foregroundStyle(turn.speaker == .learner ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(turn.speaker == .learner ? "我" : "对方")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if turn.channel == .voice {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(turn.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            turn.speaker == .learner
                ? Color.accentColor.opacity(0.08)
                : Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var composer: some View {
        HStack(spacing: 10) {
            if useVoice {
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: transcriber.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(transcriber.isRecording ? .red : .accentColor)
                }
                .buttonStyle(.plain)

                if transcriber.isRecording {
                    Text(transcriber.partialText.isEmpty ? "听写中…" : transcriber.partialText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("点麦克风开始说话")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextField("输入你的回答…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            await runtime?.submit(text, channel: .text)
            await speakLatestIfNeeded()
        }
    }

    private func toggleRecording() {
        if transcriber.isRecording {
            Task {
                let text = await transcriber.stopRecording()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                await runtime?.submit(text, channel: .voice)
                await speakLatestIfNeeded()
            }
        } else {
            Task {
                let granted = await transcriber.requestAuthorization()
                guard granted else {
                    runtime?.errorMessage = "麦克风或语音识别权限被拒绝"
                    return
                }
                try? await transcriber.startRecording()
            }
        }
    }

    private func speakLatestIfNeeded() async {
        guard useVoice else { return }
        guard let last = runtime?.session.turns.last, last.speaker == .tutor else { return }
        try? await model.player.speak(last.text)
    }

    private func saveSession() {
        guard let runtime else { return }
        do {
            try model.scenario.save(runtime.session)
            savedBanner = "已保存"
            Task {
                try? await Task.sleep(for: .seconds(2))
                savedBanner = nil
            }
        } catch {
            savedBanner = error.localizedDescription
        }
    }
}
