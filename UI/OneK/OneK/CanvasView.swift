import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .white
        canvasView.drawingPolicy = .pencilOnly
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvasView.isOpaque = true
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 5.0
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
