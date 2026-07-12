import Combine
import Foundation
import PencilKit
import UIKit

struct InkSample: Equatable {
    let x: CGFloat
    let y: CGFloat
    let timestamp: Date
    let strokeIndex: Int

    func formattedLine(using formatter: ISO8601DateFormatter) -> String {
        let timestampString = formatter.string(from: timestamp)
        return "(\(x), \(y)) @ \(timestampString)"
    }
}

@MainActor
final class ReplayBuffer: ObservableObject {
    @Published private(set) var samples: [InkSample] = []
    @Published private(set) var isReplaying = false

    var onTrackingReset: (() -> Void)?

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let logLinePattern = #/^\(([-\d.]+), ([-\d.]+)\) @ (.+)$/#

    func append(x: CGFloat, y: CGFloat, timestamp: Date, strokeIndex: Int) {
        guard !isReplaying else { return }
        let sample = InkSample(x: x, y: y, timestamp: timestamp, strokeIndex: strokeIndex)
        samples.append(sample)
        print(sample.formattedLine(using: timestampFormatter))
    }

    func clear() {
        guard !isReplaying else { return }
        samples.removeAll()
        onTrackingReset?()
    }

    static func parse(_ line: String) -> (x: CGFloat, y: CGFloat, timestamp: Date)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.firstMatch(of: logLinePattern) else { return nil }

        guard
            let x = Double(match.1),
            let y = Double(match.2)
        else { return nil }

        let timestampString = String(match.3)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let timestamp = formatter.date(from: timestampString) else { return nil }

        return (CGFloat(x), CGFloat(y), timestamp)
    }

    func load(from lines: [String], strokeGap: TimeInterval = 0.3) {
        clear()

        var strokeIndex = 0
        var previousTimestamp: Date?

        for line in lines {
            guard let parsed = Self.parse(line) else { continue }

            if let previousTimestamp,
               parsed.timestamp.timeIntervalSince(previousTimestamp) > strokeGap {
                strokeIndex += 1
            }

            samples.append(
                InkSample(
                    x: parsed.x,
                    y: parsed.y,
                    timestamp: parsed.timestamp,
                    strokeIndex: strokeIndex
                )
            )
            previousTimestamp = parsed.timestamp
        }
    }

    func replay(
        on canvasView: PKCanvasView,
        inkColor: UIColor = .yellow,
        lineWidth: CGFloat = 5
    ) async {
        guard !samples.isEmpty, !isReplaying else { return }

        isReplaying = true
        onTrackingReset?()
        defer { isReplaying = false }

        canvasView.drawing = PKDrawing()
        let ink = PKInk(.pen, color: inkColor)

        let groupedSamples = Dictionary(grouping: samples, by: \.strokeIndex)
        let strokeIndices = groupedSamples.keys.sorted()
        var completedStrokes: [PKStroke] = []
        var previousTimestamp: Date?

        for strokeIndex in strokeIndices {
            guard let strokeSamples = groupedSamples[strokeIndex]?.sorted(by: { $0.timestamp < $1.timestamp }),
                  let strokeStart = strokeSamples.first?.timestamp else {
                continue
            }

            var strokePoints: [PKStrokePoint] = []

            for sample in strokeSamples {
                if let previousTimestamp {
                    let delay = sample.timestamp.timeIntervalSince(previousTimestamp)
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
                previousTimestamp = sample.timestamp

                let timeOffset = sample.timestamp.timeIntervalSince(strokeStart)
                strokePoints.append(
                    PKStrokePoint(
                        location: CGPoint(x: sample.x, y: sample.y),
                        timeOffset: timeOffset,
                        size: CGSize(width: lineWidth, height: lineWidth),
                        opacity: 1,
                        force: 0.5,
                        azimuth: 0,
                        altitude: .pi / 2
                    )
                )

                let path = PKStrokePath(controlPoints: strokePoints, creationDate: strokeStart)
                let inProgressStroke = PKStroke(ink: ink, path: path)
                canvasView.drawing = PKDrawing(strokes: completedStrokes + [inProgressStroke])
            }

            if !strokePoints.isEmpty {
                let path = PKStrokePath(controlPoints: strokePoints, creationDate: strokeStart)
                completedStrokes.append(PKStroke(ink: ink, path: path))
            }
        }
    }
}
