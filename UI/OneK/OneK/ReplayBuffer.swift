import Combine
import Foundation
import PencilKit
import QuartzCore
import UIKit

struct InkSample: Equatable {
    let x: CGFloat
    let y: CGFloat
    let timestamp: Date
    let strokeIndex: Int
    /// Seconds after paired audio started (`CACurrentMediaTime` timeline). Primary A/V sync key.
    let timeFromAudioStart: TimeInterval?

    func formattedLine(using formatter: ISO8601DateFormatter) -> String {
        let timestampString = formatter.string(from: timestamp)
        if let timeFromAudioStart {
            return String(format: "(%.1f, %.1f) @ %@  +%.3fs", x, y, timestampString, timeFromAudioStart)
        }
        return "(\(x), \(y)) @ \(timestampString)"
    }
}

@MainActor
final class ReplayBuffer: ObservableObject {
    @Published private(set) var samples: [InkSample] = []
    @Published private(set) var isReplaying = false

    /// Set when a demo take's audio begins (`CACurrentMediaTime()`). Cleared when the take ends.
    var audioSyncStart: CFTimeInterval?

    /// When true, drawing changes are ignored (used while assistant TTS is synthesizing).
    var suppressCapture = false

    var onTrackingReset: (() -> Void)?

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let logLinePattern = #/^\(([-\d.]+), ([-\d.]+)\) @ (.+)$/#

    func append(
        x: CGFloat,
        y: CGFloat,
        timestamp: Date,
        strokeIndex: Int,
        timeFromAudioStart: TimeInterval? = nil
    ) {
        guard !isReplaying else { return }
        let sample = InkSample(
            x: x,
            y: y,
            timestamp: timestamp,
            strokeIndex: strokeIndex,
            timeFromAudioStart: timeFromAudioStart
        )
        samples.append(sample)
        print(sample.formattedLine(using: timestampFormatter))
    }

    func clear(resetTracking: Bool = true) {
        guard !isReplaying else { return }
        samples.removeAll()
        if resetTracking {
            onTrackingReset?()
        }
    }

    func load(samples newSamples: [InkSample]) {
        clear()
        samples = newSamples
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
                    strokeIndex: strokeIndex,
                    timeFromAudioStart: nil
                )
            )
            previousTimestamp = parsed.timestamp
        }
    }

    /// Replays samples. When `playbackOrigin` is set, each point is scheduled on a shared
    /// media clock (`origin + timeFromAudioStart`) so ink stays locked to audio.
    @discardableResult
    func replay(
        samples externalSamples: [InkSample]? = nil,
        on canvasView: PKCanvasView,
        clearCanvas: Bool = true,
        playbackOrigin: CFTimeInterval? = nil,
        inkColor: UIColor = .yellow,
        lineWidth: CGFloat = 1
    ) async -> [PKStroke] {
        let playbackSamples = externalSamples ?? samples
        guard !playbackSamples.isEmpty, !isReplaying else {
            return canvasView.drawing.strokes
        }

        isReplaying = true
        onTrackingReset?()
        defer { isReplaying = false }

        var completedStrokes: [PKStroke] = clearCanvas ? [] : canvasView.drawing.strokes
        if clearCanvas {
            canvasView.drawing = PKDrawing()
        }

        let ink = PKInk(.pen, color: inkColor)
        let ordered = playbackSamples.sorted { lhs, rhs in
            let lt = lhs.timeFromAudioStart ?? lhs.timestamp.timeIntervalSince1970
            let rt = rhs.timeFromAudioStart ?? rhs.timestamp.timeIntervalSince1970
            if lt == rt { return lhs.strokeIndex < rhs.strokeIndex }
            return lt < rt
        }

        let fallbackOriginDate = ordered.first?.timestamp
        var pointsByStroke: [Int: [PKStrokePoint]] = [:]
        var strokeStartDate: [Int: Date] = [:]
        var firstOffsetByStroke: [Int: TimeInterval] = [:]

        let origin = playbackOrigin ?? CACurrentMediaTime()

        for sample in ordered {
            let targetOffset: TimeInterval
            if let synced = sample.timeFromAudioStart {
                targetOffset = max(0, synced)
            } else if let fallbackOriginDate {
                targetOffset = max(0, sample.timestamp.timeIntervalSince(fallbackOriginDate))
            } else {
                targetOffset = 0
            }

            let wait = origin + targetOffset - CACurrentMediaTime()
            if wait > 0.0005 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }

            let startDate = strokeStartDate[sample.strokeIndex] ?? sample.timestamp
            if strokeStartDate[sample.strokeIndex] == nil {
                strokeStartDate[sample.strokeIndex] = sample.timestamp
                firstOffsetByStroke[sample.strokeIndex] = sample.timeFromAudioStart ?? 0
            }

            let firstOffset = firstOffsetByStroke[sample.strokeIndex] ?? 0
            let pointTimeOffset: TimeInterval
            if let synced = sample.timeFromAudioStart {
                pointTimeOffset = max(0, synced - firstOffset)
            } else {
                pointTimeOffset = sample.timestamp.timeIntervalSince(startDate)
            }

            var points = pointsByStroke[sample.strokeIndex] ?? []
            points.append(
                PKStrokePoint(
                    location: CGPoint(x: sample.x, y: sample.y),
                    timeOffset: pointTimeOffset,
                    size: CGSize(width: lineWidth, height: lineWidth),
                    opacity: 1,
                    force: 0.5,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            )
            pointsByStroke[sample.strokeIndex] = points

            let activeStrokes: [PKStroke] = pointsByStroke.keys.sorted().compactMap { index in
                guard let pts = pointsByStroke[index], !pts.isEmpty else { return nil }
                let path = PKStrokePath(
                    controlPoints: pts,
                    creationDate: strokeStartDate[index] ?? Date()
                )
                return PKStroke(ink: ink, path: path)
            }
            canvasView.drawing = PKDrawing(strokes: completedStrokes + activeStrokes)
        }

        let finished: [PKStroke] = pointsByStroke.keys.sorted().compactMap { index in
            guard let pts = pointsByStroke[index], !pts.isEmpty else { return nil }
            let path = PKStrokePath(
                controlPoints: pts,
                creationDate: strokeStartDate[index] ?? Date()
            )
            return PKStroke(ink: ink, path: path)
        }
        return completedStrokes + finished
    }
}
