//
//  ContentView.swift
//  OneK
//
//  Created by Prabal Vashisht on 5/18/26.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @StateObject private var replayBuffer = ReplayBuffer()
    @StateObject private var textToSpeech: TextToSpeech
    @StateObject private var demoSession: DemoSessionController
    @FocusState private var isNarrationFocused: Bool

    private let railWidth: CGFloat = 196

    init() {
        let tts = TextToSpeech()
        _textToSpeech = StateObject(wrappedValue: tts)
        _demoSession = StateObject(wrappedValue: DemoSessionController(textToSpeech: tts))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            CanvasView(canvasView: $canvasView, replayBuffer: replayBuffer)
                .ignoresSafeArea()

            if DemoDebug.isEnabled {
                demoSideRail
            }
        }
        .alert("Demo Error", isPresented: Binding(
            get: { demoSession.errorMessage != nil || textToSpeech.lastError != nil },
            set: { if !$0 {
                demoSession.errorMessage = nil
                textToSpeech.lastError = nil
            }}
        )) {
            Button("OK", role: .cancel) {
                demoSession.errorMessage = nil
                textToSpeech.lastError = nil
            }
        } message: {
            Text(demoSession.errorMessage ?? textToSpeech.lastError ?? "")
        }
        .onAppear {
            restoreDrawingTools()
            if DemoDebug.isEnabled {
                demoSession.reload()
            }
        }
        .onChange(of: isNarrationFocused) { _, focused in
            if !focused {
                restoreDrawingTools()
            }
        }
    }

    private func restoreDrawingTools() {
        isNarrationFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        DispatchQueue.main.async {
            _ = canvasView.becomeFirstResponder()
            toolPicker.setVisible(true, forFirstResponder: canvasView)
        }
    }

    private var demoSideRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Demo tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Assistant narration")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        if isNarrationFocused {
                            Button("Done") {
                                restoreDrawingTools()
                            }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(.yellow)
                        }
                    }

                    TextEditor(text: $demoSession.assistantScriptDraft)
                        .font(.caption)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 88, maxHeight: 140)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                        .focused($isNarrationFocused)
                        .disabled(
                            demoSession.isTakeActive
                                || demoSession.isBusy
                                || demoSession.isPlayingDemo
                        )
                }

                Group {
                    userTakeButtons
                    assistantTakeButtons

                    railButton("Play Demo") {
                        demoSession.playOneShot(on: canvasView, replayBuffer: replayBuffer)
                    }
                    .disabled(
                        demoSession.turns.isEmpty
                            || demoSession.isBusy
                            || demoSession.isPlayingDemo
                            || demoSession.isTakeActive
                            || replayBuffer.isReplaying
                    )

                    railButton("Undo Turn") {
                        demoSession.undoLastTurn()
                    }
                    .disabled(
                        demoSession.turns.isEmpty
                            || demoSession.isBusy
                            || demoSession.isPlayingDemo
                            || demoSession.isTakeActive
                    )

                    railButton("Clear Board") {
                        canvasView.drawing = PKDrawing()
                        replayBuffer.clear(resetTracking: true)
                    }
                    .disabled(
                        replayBuffer.isReplaying
                            || demoSession.isPlayingDemo
                            || demoSession.isTakeActive
                    )

                    railButton("Clear Demo") {
                        demoSession.clearAllArtifacts()
                    }
                    .disabled(
                        demoSession.isBusy
                            || demoSession.isPlayingDemo
                            || demoSession.isTakeActive
                    )

                    Button {
                        restoreDrawingTools()
                        if textToSpeech.isSpeaking || textToSpeech.isLoading {
                            textToSpeech.stop()
                        } else {
                            textToSpeech.play(text: demoSession.assistantScriptDraft)
                        }
                    } label: {
                        if textToSpeech.isLoading || demoSession.isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(textToSpeech.isSpeaking ? "Stop TTS" : "Preview TTS")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        demoSession.isPlayingDemo
                            || demoSession.isTakeActive
                            || demoSession.assistantScriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let status = demoSession.statusMessage {
                    Text(status)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
        }
        .frame(width: railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.72))
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.bottom, 8)
    }

    private func railButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            restoreDrawingTools()
            action()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var userTakeButtons: some View {
        if demoSession.isUserTakeActive {
            railButton("Finish User") {
                demoSession.finishUserTake(from: replayBuffer)
            }
            .disabled(demoSession.isBusy || demoSession.isPlayingDemo)

            railButton("Cancel User") {
                demoSession.cancelUserTake(from: replayBuffer)
            }
            .disabled(demoSession.isPlayingDemo)
        } else {
            railButton("Start User") {
                demoSession.beginUserTake(from: replayBuffer)
            }
            .disabled(
                demoSession.isBusy
                    || demoSession.isPlayingDemo
                    || demoSession.isTakeActive
                    || replayBuffer.isReplaying
            )
        }
    }

    @ViewBuilder
    private var assistantTakeButtons: some View {
        if demoSession.isAssistantTakeActive {
            railButton("Finish Asst") {
                demoSession.finishAssistantTake(from: replayBuffer)
            }
            .disabled(demoSession.isBusy || demoSession.isPlayingDemo)

            railButton("Cancel Asst") {
                demoSession.cancelAssistantTake(from: replayBuffer)
            }
            .disabled(demoSession.isPlayingDemo)
        } else {
            railButton("Start Asst") {
                demoSession.beginAssistantTake(from: replayBuffer)
            }
            .disabled(
                demoSession.isBusy
                    || demoSession.isPlayingDemo
                    || demoSession.isTakeActive
                    || replayBuffer.isReplaying
                    || demoSession.assistantScriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }
}

#Preview {
    ContentView()
}
