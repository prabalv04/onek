import SwiftUI
import PencilKit
import QuartzCore

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var replayBuffer: ReplayBuffer

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(replayBuffer: replayBuffer)
        replayBuffer.onTrackingReset = { [weak coordinator] in
            coordinator?.resetTracking()
        }
        return coordinator
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .black
        canvasView.drawingPolicy = .pencilOnly
        canvasView.tool = PKInkingTool(.pen, color: .yellow, width: 5)
        canvasView.isOpaque = true
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 5.0
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let replayBuffer: ReplayBuffer
        /// Wall-clock estimate of each stroke's start (for Date timestamps / logging).
        private var strokeStartTimes: [Date] = []
        /// Media-time estimate of each stroke's start (`CACurrentMediaTime` domain).
        private var strokeStartMediaTimes: [CFTimeInterval] = []
        private var loggedPointCounts: [Int] = []

        init(replayBuffer: ReplayBuffer) {
            self.replayBuffer = replayBuffer
        }

        func resetTracking() {
            strokeStartTimes.removeAll()
            strokeStartMediaTimes.removeAll()
            loggedPointCounts.removeAll()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !replayBuffer.isReplaying else { return }
            // Drop ink while assistant TTS is still being prepared / before audio clock exists.
            guard !replayBuffer.suppressCapture else { return }

            let strokes = canvasView.drawing.strokes

            if strokes.isEmpty {
                resetTracking()
                return
            }

            if strokes.count < strokeStartTimes.count {
                let drop = strokeStartTimes.count - strokes.count
                strokeStartTimes.removeLast(drop)
                strokeStartMediaTimes.removeLast(min(drop, strokeStartMediaTimes.count))
                loggedPointCounts.removeLast(loggedPointCounts.count - strokes.count)
            }

            for strokeIndex in strokes.indices {
                let path = strokes[strokeIndex].path
                let pointCount = path.count

                if strokeStartTimes.count <= strokeIndex {
                    guard pointCount > 0 else { continue }
                    // Anchor from the newest point: in batched callbacks it was drawn
                    // ~now, so (now - newest.timeOffset) ≈ true stroke start.
                    let newest = path[pointCount - 1]
                    strokeStartTimes.append(Date().addingTimeInterval(-newest.timeOffset))
                    strokeStartMediaTimes.append(CACurrentMediaTime() - newest.timeOffset)
                }

                if loggedPointCounts.count <= strokeIndex {
                    loggedPointCounts.append(0)
                }

                let alreadyLogged = loggedPointCounts[strokeIndex]
                let strokeStart = strokeStartTimes[strokeIndex]
                let strokeMediaStart = strokeStartMediaTimes[strokeIndex]

                guard alreadyLogged < pointCount else {
                    loggedPointCounts[strokeIndex] = pointCount
                    continue
                }

                for pointIndex in alreadyLogged..<pointCount {
                    let point = path[pointIndex]
                    let timestamp = strokeStart.addingTimeInterval(point.timeOffset)

                    let timeFromAudioStart: TimeInterval?
                    if let syncStart = replayBuffer.audioSyncStart {
                        // Keep negatives so playback can still order pre-roll correctly if any.
                        timeFromAudioStart = (strokeMediaStart + point.timeOffset) - syncStart
                    } else {
                        timeFromAudioStart = nil
                    }

                    replayBuffer.append(
                        x: point.location.x,
                        y: point.location.y,
                        timestamp: timestamp,
                        strokeIndex: strokeIndex,
                        timeFromAudioStart: timeFromAudioStart
                    )
                }

                loggedPointCounts[strokeIndex] = pointCount
            }
        }
    }
}
