import AVFoundation
import Combine
import Foundation

@MainActor
final class TextToSpeech: NSObject, ObservableObject {
    /// Conversational demo script — written for spoken pacing, not formula notation.
    static let demoScript = """
    Okay — use velocity equals v zero minus g t.
    At the top, velocity is zero... so that gives you the time to the apex.
    And the full round trip? That's just twice that.
    """

    static let speakingInstructions = """
    Speak like a calm, friendly tutor helping someone at a whiteboard.
    Natural pacing, light warmth, clear pronunciation. Not robotic or overly dramatic.
    """

    @Published private(set) var isSpeaking = false
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private var audioPlayer: AVAudioPlayer?
    private var playTask: Task<Void, Never>?

    func play(text: String = TextToSpeech.demoScript) {
        stop()
        lastError = nil

        playTask = Task {
            do {
                isLoading = true
                let data = try await fetchSpeechAudio(for: text)
                guard !Task.isCancelled else { return }
                try playAudioData(data)
            } catch {
                guard !Task.isCancelled else { return }
                isSpeaking = false
                isLoading = false
                lastError = error.localizedDescription
                print("OpenAI TTS error: \(error)")
            }
        }
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        isLoading = false
    }

    func toggle() {
        if isSpeaking || isLoading {
            stop()
        } else {
            play()
        }
    }

    private func fetchSpeechAudio(for text: String) async throws -> Data {
        let apiKey = Secrets.openAIAPIKey
        guard !apiKey.isEmpty else {
            throw TTSError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": "coral",
            "instructions": Self.speakingInstructions,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TTSError.apiError(message)
        }

        return data
    }

    private func playAudioData(_ data: Data) throws {
        configureAudioSessionIfNeeded()

        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player

        isLoading = false
        isSpeaking = true
        player.play()
    }

    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
    }
}

extension TextToSpeech: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }
}

private enum TTSError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set OPENAI_API_KEY in Secrets.swift or your Xcode scheme."
        case .invalidResponse:
            return "Invalid response from OpenAI."
        case .apiError(let message):
            return message
        }
    }
}
