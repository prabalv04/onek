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

    var body: some View {
        CanvasView(canvasView: $canvasView)
            .ignoresSafeArea()
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
