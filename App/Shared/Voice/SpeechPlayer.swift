import Foundation
import AVFoundation
import StudyCore

@MainActor
@Observable
public final class SpeechPlayer: NSObject, SpeechSynthesizer, AVSpeechSynthesizerDelegate {
    public private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String) async throws {
        guard !text.isEmpty else { return }
        stopSync()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95

        isSpeaking = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    public func stop() async {
        stopSync()
    }

    private func stopSync() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        continuation?.resume()
        continuation = nil
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
