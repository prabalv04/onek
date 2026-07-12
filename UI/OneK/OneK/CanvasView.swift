import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
        private var strokeStartTimes: [Date] = []
        private var loggedPointCounts: [Int] = []
        private let timestampFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes

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

                for pointIndex in alreadyLogged..<pointCount {
                    let point = path[pointIndex]
                    let timestamp = strokeStart.addingTimeInterval(point.timeOffset)
                    let timestampString = timestampFormatter.string(from: timestamp)
                    print("(\(point.location.x), \(point.location.y)) @ \(timestampString)")
                }

                loggedPointCounts[strokeIndex] = pointCount
            }
        }
    }
}
