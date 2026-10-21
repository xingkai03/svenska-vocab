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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = language.hasPrefix("sv") ? swedishVoice : AVSpeechSynthesisVoice(language: language)
        let base = UserDefaults.standard.object(forKey: AppSettings.speechRate) as? Double ?? 0.45
        utterance.rate = Float(slow ? base * 0.6 : base)
        synthesizer.speak(utterance)
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
