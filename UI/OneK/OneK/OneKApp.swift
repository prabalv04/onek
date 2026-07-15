//
//  OneKApp.swift
//  OneK
//
//  Created by Prabal Vashisht on 5/18/26.
//

import SwiftUI

@main
struct OneKApp: App {
    @State private var showWelcome = true

    var body: some Scene {
        WindowGroup {
            Group {
                if showWelcome {
                    WelcomeView {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            showWelcome = false
                        }
                    }
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: showWelcome)
            .preferredColorScheme(.dark)
        }
    }
}
