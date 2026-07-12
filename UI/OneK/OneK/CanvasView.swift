import SwiftUI
import PencilKit

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
        private var strokeStartTimes: [Date] = []
        private var loggedPointCounts: [Int] = []

        init(replayBuffer: ReplayBuffer) {
            self.replayBuffer = replayBuffer
        }

        func resetTracking() {
            strokeStartTimes.removeAll()
            loggedPointCounts.removeAll()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !replayBuffer.isReplaying else { return }

            let strokes = canvasView.drawing.strokes

            if strokes.isEmpty {
                resetTracking()
                return
            }

            if strokes.count < strokeStartTimes.count {
                strokeStartTimes.removeLast(strokeStartTimes.count - strokes.count)
                loggedPointCounts.removeLast(loggedPointCounts.count - strokes.count)
            }

            for strokeIndex in strokes.indices {
                let path = strokes[strokeIndex].path
                let pointCount = path.count

                if strokeStartTimes.count <= strokeIndex {
                    guard pointCount > 0 else { continue }
                    let firstPoint = path[0]
                    strokeStartTimes.append(Date().addingTimeInterval(-firstPoint.timeOffset))
                }

                if loggedPointCounts.count <= strokeIndex {
                    loggedPointCounts.append(0)
                }

                let alreadyLogged = loggedPointCounts[strokeIndex]
                let strokeStart = strokeStartTimes[strokeIndex]

                guard alreadyLogged < pointCount else {
                    loggedPointCounts[strokeIndex] = pointCount
                    continue
                }

                for pointIndex in alreadyLogged..<pointCount {
                    let point = path[pointIndex]
                    let timestamp = strokeStart.addingTimeInterval(point.timeOffset)
                    replayBuffer.append(
                        x: point.location.x,
                        y: point.location.y,
                        timestamp: timestamp,
                        strokeIndex: strokeIndex
                    )
                }

                loggedPointCounts[strokeIndex] = pointCount
            }
        }
    }
}
