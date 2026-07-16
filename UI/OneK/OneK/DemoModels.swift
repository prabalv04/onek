import Foundation

struct CodableInkSample: Codable, Equatable {
    var x: Double
    var y: Double
    var timestamp: Date
    var strokeIndex: Int
    var timeFromAudioStart: Double?

    init(sample: InkSample) {
        x = Double(sample.x)
        y = Double(sample.y)
        timestamp = sample.timestamp
        strokeIndex = sample.strokeIndex
        timeFromAudioStart = sample.timeFromAudioStart
    }

    var inkSample: InkSample {
        InkSample(
            x: CGFloat(x),
            y: CGFloat(y),
            timestamp: timestamp,
            strokeIndex: strokeIndex,
            timeFromAudioStart: timeFromAudioStart
        )
    }
}

enum DemoTurnRole: String, Codable {
    case user
    case assistant
}

struct DemoTurn: Codable, Identifiable, Equatable {
    let id: UUID
    let role: DemoTurnRole
    let script: String?
    let samples: [CodableInkSample]
    let audioFileName: String?
    /// Wall-clock moment when paired audio capture/playback began (legacy / debug).
    let audioStartedAt: Date?
    let createdAt: Date

    var inkSamples: [InkSample] {
        samples.map(\.inkSample)
    }

    var hasSyncedInk: Bool {
        samples.contains { $0.timeFromAudioStart != nil }
    }
}

struct DemoManifest: Codable, Equatable {
    var turns: [DemoTurn]
}

enum DemoScripts {
    /// Scripts used when saving successive assistant turns (index = assistant turn count).
    static let assistant: [String] = [
        """
        Okay — use velocity equals v zero minus g t.
        At the top, velocity is zero... so that gives you the time to the apex.
        And the full round trip? That's just twice that.
        """,
        """
        Nice — that's the time to the apex.
        Multiply by two for the round trip, and you're done.
        """
    ]

    static func script(forAssistantIndex index: Int) -> String {
        guard !assistant.isEmpty else { return TextToSpeech.demoScript }
        if index < assistant.count {
            return assistant[index]
        }
        return assistant[index % assistant.count]
    }
}
