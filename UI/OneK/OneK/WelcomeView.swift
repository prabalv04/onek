import SwiftUI
import UIKit

struct WelcomeView: View {
    var onFinished: () -> Void

    /// 0 = full proverb, 1 = only "1000" remains.
    @State private var collapseProgress: CGFloat = 0
    @State private var zerosToKProgress: CGFloat = 0
    @State private var oneExpandProgress: CGFloat = 0
    @State private var didStart = false

    private let brandFont = Font(WelcomeMetrics.uiFont)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(alignment: .center, spacing: 0) {
                ProverbLeadingChrome(progress: collapseProgress, font: brandFont)

                HStack(alignment: .center, spacing: 0) {
                    OneExpandMorph(progress: oneExpandProgress, font: brandFont)
                    ZerosToKMorph(progress: zerosToKProgress, font: brandFont)
                }

                ProverbTrailingChrome(progress: collapseProgress, font: brandFont)
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
        // Hold "1 [picture] = 1000 words"
        try? await Task.sleep(for: .milliseconds(2400))

        // Collapse chrome so only "1000" remains (centered as sides peel away)
        withAnimation(.timingCurve(0.33, 0.0, 0.2, 1.0, duration: 0.85)) {
            collapseProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(1000))

        // Brief beat on "1000"
        try? await Task.sleep(for: .milliseconds(350))

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

// MARK: - Proverb chrome ("1 [thumb] = " ... " words")

private struct ProverbLeadingChrome: View, Animatable {
    var progress: CGFloat
    var font: Font

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        let opacity = 1 - WelcomeMetrics.smoothstep(0.0, 0.65, p)
        let scale = 1 - 0.08 * p
        let widthFactor = 1 - WelcomeMetrics.smoothstep(0.05, 0.9, p)

        HStack(alignment: .center, spacing: WelcomeMetrics.phraseSpacing) {
            Text("1")
                .font(font)
                .fixedSize()

            PictureThumbnail(size: WelcomeMetrics.thumbnailSize)

            Text("=")
                .font(font)
                .fixedSize()
        }
        .padding(.trailing, WelcomeMetrics.phraseSpacing)
        .opacity(opacity)
        .scaleEffect(scale, anchor: .trailing)
        .frame(width: WelcomeMetrics.leadingChromeWidth * widthFactor, alignment: .trailing)
        .clipped()
        .transaction { $0.animation = nil }
    }
}

private struct ProverbTrailingChrome: View, Animatable {
    var progress: CGFloat
    var font: Font

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        let opacity = 1 - WelcomeMetrics.smoothstep(0.0, 0.65, p)
        let scale = 1 - 0.08 * p
        let widthFactor = 1 - WelcomeMetrics.smoothstep(0.05, 0.9, p)

        Text(" words")
            .font(font)
            .fixedSize()
            .opacity(opacity)
            .scaleEffect(scale, anchor: .leading)
            .frame(width: WelcomeMetrics.trailingChromeWidth * widthFactor, alignment: .leading)
            .clipped()
            .transaction { $0.animation = nil }
    }
}

/// Small chalkboard-style picture mark (reads as a thumbnail, no asset required).
private struct PictureThumbnail: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.42),
                            Color(white: 0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Soft "sun"
            Circle()
                .fill(Color(white: 0.95).opacity(0.9))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.18, y: -size * 0.16)

            // Foreground hills
            Ellipse()
                .fill(Color(white: 0.28).opacity(0.95))
                .frame(width: size * 0.9, height: size * 0.55)
                .offset(x: -size * 0.1, y: size * 0.32)

            Ellipse()
                .fill(Color(white: 0.18).opacity(0.95))
                .frame(width: size * 0.85, height: size * 0.5)
                .offset(x: size * 0.18, y: size * 0.38)

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .accessibilityLabel("picture")
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
    static let fontSize: CGFloat = 56
    static let phraseSpacing: CGFloat = 14
    static let thumbnailSize: CGFloat = 52

    static let uiFont: UIFont = {
        UIFont(name: "Futura-Medium", size: fontSize)
            ?? UIFont(name: "Futura", size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .medium)
    }()

    static func width(of string: String) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: uiFont]).width)
    }

    static var leadingChromeWidth: CGFloat {
        width(of: "1") + phraseSpacing + thumbnailSize + phraseSpacing + width(of: "=") + phraseSpacing
    }

    static var trailingChromeWidth: CGFloat {
        width(of: " words")
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

#Preview {
    WelcomeView(onFinished: {})
}
