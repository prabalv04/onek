import Combine
import Foundation
import PencilKit
import QuartzCore

@MainActor
final class DemoSessionController: ObservableObject {
    @Published private(set) var turns: [DemoTurn] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isPlayingDemo = false
    @Published private(set) var isUserTakeActive = false
    @Published private(set) var isAssistantTakeActive = false
    /// Editable narration for the next assistant take (TTS).
    @Published var assistantScriptDraft: String = DemoScripts.script(forAssistantIndex: 0)
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let textToSpeech: TextToSpeech
    private let voiceRecorder = VoiceRecorder()
    private var pendingAssistantAudio: Data?
    private var pendingAssistantScript: String?
    private var pendingUserAudioStartedAt: Date?
    private var pendingAssistantAudioStartedAt: Date?

    init(textToSpeech: TextToSpeech) {
        self.textToSpeech = textToSpeech
        reload()
    }

    var turnCountLabel: String {
        let users = turns.filter { $0.role == .user }.count
        let assistants = turns.filter { $0.role == .assistant }.count
        return "\(turns.count) turns · \(users) user · \(assistants) asst"
    }

    var nextAssistantScript: String {
        let assistantCount = turns.filter { $0.role == .assistant }.count
        return DemoScripts.script(forAssistantIndex: assistantCount)
    }

    var isTakeActive: Bool {
        isUserTakeActive || isAssistantTakeActive
    }

    func reload() {
        guard DemoDebug.isEnabled else {
            turns = []
            return
        }
        do {
            turns = try DemoArtifactStore.loadManifest().turns
            assistantScriptDraft = nextAssistantScript
            statusMessage = turns.isEmpty ? "No demo turns saved" : turnCountLabel
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mode 1: User talking + drawing

    func beginUserTake(from buffer: ReplayBuffer) {
        guard DemoDebug.isEnabled else { return }
        guard !isTakeActive, !isBusy, !isPlayingDemo else { return }

        isBusy = true
        errorMessage = nil
        statusMessage = "Requesting microphone…"

        Task {
            let granted = await voiceRecorder.requestPermission()
            guard granted else {
                isBusy = false
                errorMessage = VoiceRecorderError.permissionDenied.localizedDescription
                return
            }

            do {
                buffer.clear(resetTracking: false)
                let mediaStart = try voiceRecorder.start()
                buffer.audioSyncStart = mediaStart
                pendingUserAudioStartedAt = Date()
                isUserTakeActive = true
                isBusy = false
                statusMessage = "Recording — talk & draw. Tap Finish User when done."
            } catch {
                buffer.audioSyncStart = nil
                pendingUserAudioStartedAt = nil
                isBusy = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func finishUserTake(from buffer: ReplayBuffer) {
        guard DemoDebug.isEnabled else { return }
        guard isUserTakeActive else { return }

        guard let recordedURL = voiceRecorder.stop() else {
            errorMessage = "No microphone audio captured."
            cancelUserTake(from: buffer)
            return
        }

        guard !buffer.samples.isEmpty else {
            try? FileManager.default.removeItem(at: recordedURL)
            errorMessage = "Draw something while talking, then finish."
            buffer.audioSyncStart = nil
            pendingUserAudioStartedAt = nil
            isUserTakeActive = false
            return
        }

        isBusy = true
        do {
            let audioData = try Data(contentsOf: recordedURL)
            try? FileManager.default.removeItem(at: recordedURL)

            let fileName = "user-\(UUID().uuidString).m4a"
            _ = try DemoArtifactStore.saveAudio(audioData, fileName: fileName)

            let turn = DemoTurn(
                id: UUID(),
                role: .user,
                script: nil,
                samples: buffer.samples.map(CodableInkSample.init),
                audioFileName: fileName,
                audioStartedAt: pendingUserAudioStartedAt,
                createdAt: Date()
            )
            try append(turn)
            buffer.audioSyncStart = nil
            buffer.clear(resetTracking: false)
            pendingUserAudioStartedAt = nil
            isUserTakeActive = false
            isBusy = false
            statusMessage = turn.hasSyncedInk
                ? "Saved user pair (talk + ink, synced)"
                : "Saved user pair (warning: missing sync offsets)"
        } catch {
            buffer.audioSyncStart = nil
            pendingUserAudioStartedAt = nil
            isBusy = false
            isUserTakeActive = false
            errorMessage = error.localizedDescription
        }
    }

    func cancelUserTake(from buffer: ReplayBuffer) {
        voiceRecorder.stopAndDiscard()
        buffer.audioSyncStart = nil
        pendingUserAudioStartedAt = nil
        isUserTakeActive = false
        isBusy = false
        buffer.clear(resetTracking: false)
        statusMessage = "Cancelled user take"
    }

    // MARK: - Mode 2: TTS narrating + drawing

    func beginAssistantTake(from buffer: ReplayBuffer) {
        guard DemoDebug.isEnabled else { return }
        guard !isTakeActive, !isBusy, !isPlayingDemo else { return }

        let script = assistantScriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            errorMessage = "Type the assistant narration text before starting."
            return
        }

        isBusy = true
        statusMessage = "Preparing assistant audio… (don’t draw yet)"
        errorMessage = nil
        // Ignore any ink until TTS audio is actually playing.
        buffer.suppressCapture = true

        Task {
            do {
                let audioData = try await textToSpeech.synthesizeAudio(for: script)
                pendingAssistantAudio = audioData
                pendingAssistantScript = script

                // Drop anything captured before audio; keep board ink tracking intact.
                buffer.clear(resetTracking: false)

                isAssistantTakeActive = true
                isBusy = false
                pendingAssistantAudioStartedAt = Date()

                // Start audio and bind the sync clock in the same turn, then allow capture.
                let mediaStart = try textToSpeech.startPlayback(data: audioData)
                buffer.audioSyncStart = mediaStart
                buffer.suppressCapture = false
                // Clear again so only post-audio ink is stored for this pair.
                buffer.clear(resetTracking: false)

                statusMessage = "Draw now — TTS playing. Tap Finish Asst when done."
                await textToSpeech.waitUntilFinished()

                if isAssistantTakeActive {
                    statusMessage = "Audio done — finish drawing, then tap Finish Asst."
                }
            } catch {
                isBusy = false
                isAssistantTakeActive = false
                pendingAssistantAudio = nil
                pendingAssistantScript = nil
                pendingAssistantAudioStartedAt = nil
                buffer.audioSyncStart = nil
                buffer.suppressCapture = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func finishAssistantTake(from buffer: ReplayBuffer) {
        guard DemoDebug.isEnabled else { return }
        guard isAssistantTakeActive else { return }
        guard let audioData = pendingAssistantAudio else {
            errorMessage = "Missing assistant audio — start the take again."
            cancelAssistantTake(from: buffer)
            return
        }

        // Only keep points stamped against the audio clock.
        let syncedSamples = buffer.samples.filter { sample in
            guard let t = sample.timeFromAudioStart else { return false }
            return t >= -0.05
        }
        guard !syncedSamples.isEmpty else {
            errorMessage = "Draw while TTS is playing (after “Draw now”), then finish."
            return
        }

        textToSpeech.stop()
        isBusy = true

        do {
            let fileName = "assistant-\(UUID().uuidString).mp3"
            _ = try DemoArtifactStore.saveAudio(audioData, fileName: fileName)

            let turn = DemoTurn(
                id: UUID(),
                role: .assistant,
                script: pendingAssistantScript,
                samples: syncedSamples.map(CodableInkSample.init),
                audioFileName: fileName,
                audioStartedAt: pendingAssistantAudioStartedAt,
                createdAt: Date()
            )
            try append(turn)
            buffer.audioSyncStart = nil
            buffer.suppressCapture = false
            buffer.clear(resetTracking: false)
            pendingAssistantAudio = nil
            pendingAssistantScript = nil
            pendingAssistantAudioStartedAt = nil
            isAssistantTakeActive = false
            isBusy = false
            assistantScriptDraft = nextAssistantScript
            statusMessage = "Saved assistant pair (TTS + ink, synced)"
        } catch {
            isBusy = false
            errorMessage = error.localizedDescription
        }
    }

    func cancelAssistantTake(from buffer: ReplayBuffer) {
        textToSpeech.stop()
        pendingAssistantAudio = nil
        pendingAssistantScript = nil
        pendingAssistantAudioStartedAt = nil
        buffer.audioSyncStart = nil
        buffer.suppressCapture = false
        isAssistantTakeActive = false
        isBusy = false
        buffer.clear(resetTracking: false)
        statusMessage = "Cancelled assistant take"
    }

    // MARK: - Library

    func undoLastTurn() {
        guard DemoDebug.isEnabled, !turns.isEmpty, !isTakeActive else { return }
        var manifestTurns = turns
        let removed = manifestTurns.removeLast()
        if let audio = removed.audioFileName {
            let url = DemoArtifactStore.audioURL(fileName: audio)
            try? FileManager.default.removeItem(at: url)
        }
        do {
            try DemoArtifactStore.saveManifest(DemoManifest(turns: manifestTurns))
            turns = manifestTurns
            statusMessage = "Removed last turn · \(turnCountLabel)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearAllArtifacts() {
        guard DemoDebug.isEnabled, !isTakeActive else { return }
        do {
            try DemoArtifactStore.deleteAll()
            turns = []
            statusMessage = "Cleared demo artifacts"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playOneShot(
        on canvasView: PKCanvasView,
        replayBuffer: ReplayBuffer
    ) {
        guard DemoDebug.isEnabled else { return }
        guard !isTakeActive else {
            errorMessage = "Finish or cancel the active take first."
            return
        }
        guard !turns.isEmpty else {
            errorMessage = "Save at least one turn before playing the demo."
            return
        }
        guard !isPlayingDemo, !isBusy, !replayBuffer.isReplaying else { return }

        isPlayingDemo = true
        statusMessage = "Playing one-shot demo…"
        errorMessage = nil

        Task {
            defer {
                isPlayingDemo = false
                statusMessage = "Demo finished · \(turnCountLabel)"
            }

            canvasView.drawing = PKDrawing()
            replayBuffer.clear(resetTracking: true)

            for (index, turn) in turns.enumerated() {
                statusMessage = "Turn \(index + 1)/\(turns.count) · \(turn.role.rawValue)"
                await playTurn(turn, on: canvasView, replayBuffer: replayBuffer)
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func playTurn(
        _ turn: DemoTurn,
        on canvasView: PKCanvasView,
        replayBuffer: ReplayBuffer
    ) async {
        let inkSamples = turn.inkSamples

        guard let fileName = turn.audioFileName else {
            _ = await replayBuffer.replay(
                samples: inkSamples,
                on: canvasView,
                clearCanvas: false
            )
            return
        }

        let url = DemoArtifactStore.audioURL(fileName: fileName)
        do {
            let data = try Data(contentsOf: url)

            // Shared media-time origin: ink schedules against this exact clock.
            let origin = try textToSpeech.startPlayback(data: data)

            async let ink: Void = {
                _ = await replayBuffer.replay(
                    samples: inkSamples,
                    on: canvasView,
                    clearCanvas: false,
                    playbackOrigin: origin
                )
            }()

            await textToSpeech.waitUntilFinished()
            await ink
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func append(_ turn: DemoTurn) throws {
        var manifest = try DemoArtifactStore.loadManifest()
        manifest.turns.append(turn)
        try DemoArtifactStore.saveManifest(manifest)
        turns = manifest.turns
    }
}
