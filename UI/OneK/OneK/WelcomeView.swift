import SwiftUI
import UIKit

struct WelcomeView: View {
    var onFinished: () -> Void

    @State private var zerosToKProgress: CGFloat = 0
    @State private var oneExpandProgress: CGFloat = 0
    @State private var didStart = false

    private static let fontSize: CGFloat = 76

    private static let uiFont: UIFont = {
        UIFont(name: "Futura-Medium", size: fontSize)
            ?? UIFont(name: "Futura", size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .medium)
    }()

    private static func width(of string: String) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: uiFont]).width)
    }

    private let brandFont = Font(uiFont)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(alignment: .center, spacing: 0) {
                OneExpandMorph(progress: oneExpandProgress, font: brandFont)
                ZerosToKMorph(progress: zerosToKProgress, font: brandFont)
            }
            .foregroundStyle(.white)
            .accessibilityLabel("OneK")
        }
        .statusBarHidden(true)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            Task { @MainActor in
                await runIntro()
            }
        }
    }

    @MainActor
    private func runIntro() async {
        try? await Task.sleep(for: .milliseconds(400))

        withAnimation(.timingCurve(0.33, 0.0, 0.2, 1.0, duration: 1.05)) {
            zerosToKProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(1150))

        withAnimation(.timingCurve(0.33, 0.0, 0.2, 1.0, duration: 1.0)) {
            oneExpandProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(1250))

        try? await Task.sleep(for: .milliseconds(550))
        onFinished()
    }
}

// MARK: - Continuous morphs (Animatable = smooth per-frame interpolation)

private struct ZerosToKMorph: View, Animatable {
    var progress: CGFloat
    var font: Font

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let zerosWidth = WelcomeMetrics.width(of: "000")
    private static let kWidth = WelcomeMetrics.width(of: "K")

    var body: some View {
        let p = min(max(progress, 0), 1)
        let compress = 1 + (Self.kWidth / Self.zerosWidth - 1) * p
        let width = Self.zerosWidth + (Self.kWidth - Self.zerosWidth) * p
        let zerosOpacity = 1 - WelcomeMetrics.smoothstep(0.12, 0.78, p)
        let zerosBlur = WelcomeMetrics.smoothstep(0.08, 0.5, p) * 2.2
            * (1 - WelcomeMetrics.smoothstep(0.65, 1.0, p))
        let kOpacity = WelcomeMetrics.smoothstep(0.22, 0.88, p)
        let kScale = 0.9 + 0.1 * WelcomeMetrics.smoothstep(0.22, 1.0, p)

        ZStack(alignment: .leading) {
            Text("000")
                .font(font)
                .opacity(zerosOpacity)
                .blur(radius: zerosBlur)
                .scaleEffect(x: compress, y: 1, anchor: .leading)
                .fixedSize()

            Text("K")
                .font(font)
                .opacity(kOpacity)
                .scaleEffect(kScale, anchor: .leading)
                .fixedSize()
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        // Kill implicit animations so only animatableData drives motion.
        .transaction { $0.animation = nil }
    }
}

private struct OneExpandMorph: View, Animatable {
    var progress: CGFloat
    var font: Font

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let digitWidth = WelcomeMetrics.width(of: "1")
    private static let oneWidth = WelcomeMetrics.width(of: "One")

    var body: some View {
        let p = min(max(progress, 0), 1)
        let width = Self.digitWidth + (Self.oneWidth - Self.digitWidth) * p
        let digitOpacity = 1 - WelcomeMetrics.smoothstep(0.05, 0.45, p)
        let wordOpacity = WelcomeMetrics.smoothstep(0.15, 0.7, p)
        let wordOffset = -10 * (1 - WelcomeMetrics.smoothstep(0.0, 0.85, p))

        ZStack(alignment: .leading) {
            Text("1")
                .font(font)
                .opacity(digitOpacity)
                .fixedSize()

            Text("One")
                .font(font)
                .opacity(wordOpacity)
                .offset(x: wordOffset)
                .fixedSize()
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .transaction { $0.animation = nil }
    }
}

private enum WelcomeMetrics {
    static let fontSize: CGFloat = 76

    static let uiFont: UIFont = {
        UIFont(name: "Futura-Medium", size: fontSize)
            ?? UIFont(name: "Futura", size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .medium)
    }()

    static func width(of string: String) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: uiFont]).width)
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

#Preview {
    WelcomeView(onFinished: {})
}
