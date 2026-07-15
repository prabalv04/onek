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
    @StateObject private var textToSpeech = TextToSpeech()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CanvasView(canvasView: $canvasView, replayBuffer: replayBuffer)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Button {
                    textToSpeech.toggle()
                } label: {
                    if textToSpeech.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text(textToSpeech.isSpeaking ? "Stop" : "Play")
                    }
                }
                .disabled(textToSpeech.isLoading && !textToSpeech.isSpeaking)

                Button("Clear") {
                    canvasView.drawing = PKDrawing()
                    replayBuffer.clear()
                }
                .disabled(replayBuffer.isReplaying)

                Button("Replay") {
                    Task {
                        await replayBuffer.replay(on: canvasView)
                    }
                }
                .disabled(replayBuffer.samples.isEmpty || replayBuffer.isReplaying)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .alert("TTS Error", isPresented: Binding(
            get: { textToSpeech.lastError != nil },
            set: { if !$0 { textToSpeech.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {
                textToSpeech.lastError = nil
            }
        } message: {
            Text(textToSpeech.lastError ?? "")
        }
        .onAppear {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
    }
}

#Preview {
    ContentView()
}
