import AVFoundation
import Foundation
import QuartzCore

@MainActor
final class VoiceRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    var isRecording: Bool { recorder?.isRecording == true }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Starts recording and returns `CACurrentMediaTime()` at the moment capture begins.
    @discardableResult
    func start() throws -> CFTimeInterval {
        stopAndDiscard()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onek-user-\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        let startedAt = CACurrentMediaTime()
        guard recorder.record() else {
            throw VoiceRecorderError.failedToStart
        }
        self.recorder = recorder
        return startedAt
    }

    /// Stops recording and returns the audio file URL (still in temp).
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return recordingURL
    }

    func stopAndDiscard() {
        let url = stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }
}

enum VoiceRecorderError: LocalizedError {
    case permissionDenied
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required to record your talking + drawing take."
        case .failedToStart:
            return "Could not start microphone recording."
        }
    }
}
