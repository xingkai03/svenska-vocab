import AVFoundation
import SwiftUI

/// Swedish text-to-speech using the system's sv-SE voices.
@MainActor
final class SpeechService: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// The best installed Swedish voice (premium > enhanced > default).
    var swedishVoice: AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("sv") }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "sv-SE")
    }

    var hasSwedishVoice: Bool { swedishVoice != nil }

    func speak(_ text: String, slow: Bool = false, language: String = "sv-SE") {
        speak([text], slow: slow, language: language)
    }

    /// Speaks the word (when given) and then the example sentence, if "Pronounce example sentences
    /// automatically" is on. Used where an example comes into view.
    func speak(_ word: String?, thenExample example: String) {
        let examples = UserDefaults.standard.object(forKey: AppSettings.autoSpeakExamples) as? Bool ?? true
        speak([word ?? "", examples ? example : ""])
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Speaks the texts one after another, with a short pause between them.
    private func speak(_ texts: [String], slow: Bool = false, language: String = "sv-SE") {
        let texts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        stop()
        let voice = language.hasPrefix("sv") ? swedishVoice : AVSpeechSynthesisVoice(language: language)
        let base = UserDefaults.standard.object(forKey: AppSettings.speechRate) as? Double ?? 0.45
        for (i, text) in texts.enumerated() {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = Float(slow ? base * 0.6 : base)
            if i > 0 { utterance.preUtteranceDelay = 0.5 }
            synthesizer.speak(utterance)
        }
    }
}

/// Speaker button used throughout the app.
struct SpeakButton: View {
    @EnvironmentObject private var speech: SpeechService
    let text: String
    var slow = false
    var font: Font = .title3

    var body: some View {
        Button {
            speech.speak(text, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : "speaker.wave.2.fill")
                .font(font)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(slow ? "Pronounce slowly" : "Pronounce")
    }
}
