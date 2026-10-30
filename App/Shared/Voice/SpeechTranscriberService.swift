import Foundation
import Speech
import AVFoundation

@MainActor
@Observable
public final class SpeechTranscriberService {
    public private(set) var isRecording = false
    public private(set) var partialText = ""
    public private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var stopContinuation: CheckedContinuation<String, Never>?

    public init() {}

    public var isSupported: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func startRecording() async throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let engine = AVAudioEngine()
        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.shouldReportPartialResults = true
        bufferRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw SpeechError.audioFormatUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            bufferRequest.append(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.request = bufferRequest
        self.partialText = ""
        self.errorMessage = nil
        self.isRecording = true

        task = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.teardown()
                    self.resumeStop(with: self.partialText)
                }
            }
        }
    }

    public func stopRecording() async -> String {
        guard isRecording else { return partialText }
        request?.endAudio()
        isRecording = false

        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                self.teardown()
                self.resumeStop(with: self.partialText)
            }
        }
    }

    public func cancel() {
        teardown()
        isRecording = false
        partialText = ""
        resumeStop(with: "")
    }

    private func teardown() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
    }

    private func resumeStop(with text: String) {
        guard let continuation = stopContinuation else { return }
        stopContinuation = nil
        continuation.resume(returning: text)
    }
}

public enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case audioFormatUnavailable

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "语音识别当前不可用"
        case .audioFormatUnavailable:
            return "麦克风不可用或没有授权"
        }
    }
}
