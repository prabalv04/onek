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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CanvasView(canvasView: $canvasView, replayBuffer: replayBuffer)
                .ignoresSafeArea()

            HStack(spacing: 12) {
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
