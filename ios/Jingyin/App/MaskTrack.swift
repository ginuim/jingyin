import CoreGraphics
import Foundation

/// A rectangle in display-oriented video coordinates.
///
/// The origin is at the top-left of the displayed video and every component is
/// clamped to `0...1`. Keeping this independent from pixels makes the same track
/// usable by the SwiftUI preview and the final Core Image export.
struct NormalizedVideoRect: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        let safeX = Self.unitValue(x)
        let safeY = Self.unitValue(y)
        self.x = safeX
        self.y = safeY
        self.width = min(Self.unitValue(width), 1 - safeX)
        self.height = min(Self.unitValue(height), 1 - safeY)
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts Vision's normalized bottom-left rectangle into the app's
    /// display-oriented, top-left normalized coordinate space.
    init(visionBoundingBox: CGRect) {
        self.init(
            x: visionBoundingBox.minX,
            y: 1 - visionBoundingBox.maxY,
            width: visionBoundingBox.width,
            height: visionBoundingBox.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    /// Vision requests use a normalized bottom-left origin. Face detection and
    /// tracking pass through this conversion before becoming MaskTrack data.
    var visionBoundingBox: CGRect {
        CGRect(
            x: x,
            y: 1 - y - height,
            width: width,
            height: height
        )
    }

    /// Scales around the current center while keeping the rectangle fully
    /// inside normalized video bounds. Preview and export both consume this
    /// same rectangle, so coverage adjustments cannot diverge between paths.
    func scaledAroundCenter(
        by factor: Double,
        minimumDimension: Double = 0.05
    ) -> Self {
        guard factor.isFinite, factor > 0 else { return self }
        let minimum = min(max(minimumDimension, 0), 1)
        let targetWidth = min(max(width * factor, minimum), 1)
        let targetHeight = min(max(height * factor, minimum), 1)
        let centerX = x + width / 2
        let centerY = y + height / 2
        return Self(
            x: min(max(centerX - targetWidth / 2, 0), 1 - targetWidth),
            y: min(max(centerY - targetHeight / 2, 0), 1 - targetHeight),
            width: targetWidth,
            height: targetHeight
        )
    }

    /// Expands a tight Vision face rectangle to include forehead, ears and
    /// chin. The slight upward shift gives extra safety around the forehead.
    func expandedForFaceCoverage() -> Self {
        let targetWidth = min(max(width * 1.48, 0.08), 1)
        let targetHeight = min(max(height * 1.62, 0.10), 1)
        let centerX = x + width / 2
        let centerY = y + height / 2 - height * 0.05
        return Self(
            x: min(max(centerX - targetWidth / 2, 0), 1 - targetWidth),
            y: min(max(centerY - targetHeight / 2, 0), 1 - targetHeight),
            width: targetWidth,
            height: targetHeight
        )
    }

    /// Converts to a top-left-origin preview rectangle inside the displayed
    /// video bounds. Callers should pass the actual aspect-fit video bounds,
    /// excluding any letterboxing around it.
    func rect(inPreviewBounds bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + CGFloat(x) * bounds.width,
            y: bounds.minY + CGFloat(y) * bounds.height,
            width: CGFloat(width) * bounds.width,
            height: CGFloat(height) * bounds.height
        )
    }

    /// Converts to Core Image's bottom-left-origin coordinates.
    func rect(inCoreImageExtent extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + CGFloat(x) * extent.width,
            y: extent.minY + CGFloat(1 - y - height) * extent.height,
            width: CGFloat(width) * extent.width,
            height: CGFloat(height) * extent.height
        )
    }

    static func interpolate(
        from start: Self,
        to end: Self,
        progress: Double
    ) -> Self {
        let amount = unitValue(progress)
        return Self(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount,
            width: start.width + (end.width - start.width) * amount,
            height: start.height + (end.height - start.height) * amount
        )
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

enum MaskTrackShape: String, Codable, CaseIterable, Sendable {
    case ellipse
    case rectangle
}

enum MaskTrackSource: String, Codable, Sendable {
    case manual
    case detectedFace
}

enum MaskTrackingState: String, Codable, Sendable {
    case notTracked
    case tracking
    case tracked
    case lost
    case needsRetracking
}

struct MaskKeyframe: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Origin: String, Codable, Sendable {
        case manual
        case automaticTracking
    }

    let id: UUID
    var timeSeconds: TimeInterval
    var rect: NormalizedVideoRect
    var origin: Origin

    init(
        id: UUID = UUID(),
        timeSeconds: TimeInterval,
        rect: NormalizedVideoRect,
        origin: Origin = .manual
    ) {
        self.id = id
        self.timeSeconds = Self.validTime(timeSeconds)
        self.rect = rect
        self.origin = origin
    }

    private static func validTime(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
}

struct MaskTrack: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var shape: MaskTrackShape
    var source: MaskTrackSource
    var sourceIdentifier: String?
    var isEnabled: Bool
    var activeFromSeconds: TimeInterval?
    var activeUntilSeconds: TimeInterval?
    var trackingState: MaskTrackingState
    var trackingLostAtSeconds: TimeInterval?
    private(set) var keyframes: [MaskKeyframe]

    init(
        id: UUID = UUID(),
        shape: MaskTrackShape,
        source: MaskTrackSource = .manual,
        sourceIdentifier: String? = nil,
        isEnabled: Bool = true,
        activeFromSeconds: TimeInterval? = nil,
        activeUntilSeconds: TimeInterval? = nil,
        trackingState: MaskTrackingState = .notTracked,
        trackingLostAtSeconds: TimeInterval? = nil,
        keyframes: [MaskKeyframe] = []
    ) {
        self.id = id
        self.shape = shape
        self.source = source
        self.sourceIdentifier = sourceIdentifier
        self.isEnabled = isEnabled
        self.activeFromSeconds = Self.validOptionalTime(activeFromSeconds)
        self.activeUntilSeconds = Self.validOptionalTime(activeUntilSeconds)
        self.trackingState = trackingState
        self.trackingLostAtSeconds = Self.validOptionalTime(trackingLostAtSeconds)
        self.keyframes = Self.ordered(keyframes)
    }

    mutating func setKeyframe(_ keyframe: MaskKeyframe) {
        let sameTimeTolerance = 1.0 / 600.0
        if let index = keyframes.firstIndex(where: {
            $0.id == keyframe.id
                || abs($0.timeSeconds - keyframe.timeSeconds) < sameTimeTolerance
        }) {
            keyframes[index] = keyframe
        } else {
            keyframes.append(keyframe)
        }
        keyframes = Self.ordered(keyframes)
    }

    mutating func removeKeyframes(after timeSeconds: TimeInterval) {
        let time = timeSeconds.isFinite ? max(0, timeSeconds) : 0
        keyframes.removeAll { $0.timeSeconds > time + 1.0 / 600.0 }
    }

    mutating func applyTrackingResult(
        keyframes trackedKeyframes: [MaskKeyframe],
        lostAtSeconds: TimeInterval?
    ) {
        for keyframe in trackedKeyframes {
            setKeyframe(keyframe)
        }
        trackingLostAtSeconds = Self.validOptionalTime(lostAtSeconds)
        trackingState = trackingLostAtSeconds == nil ? .tracked : .lost
    }

    mutating func markManualCorrection(at timeSeconds: TimeInterval) {
        guard source == .detectedFace,
              trackingState == .lost || trackingState == .needsRetracking else {
            return
        }
        let time = timeSeconds.isFinite ? max(0, timeSeconds) : 0
        if let trackingLostAtSeconds, time + 0.12 < trackingLostAtSeconds {
            return
        }
        self.trackingLostAtSeconds = nil
        trackingState = .needsRetracking
    }

    @discardableResult
    mutating func removeKeyframe(id: MaskKeyframe.ID) -> Bool {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        keyframes.remove(at: index)
        return true
    }

    /// Returns the linearly interpolated rectangle at a video time.
    ///
    /// Outside the first and last keyframes the nearest keyframe is held. Use
    /// `activeFromSeconds` and `activeUntilSeconds` for subjects that enter or
    /// leave the shot.
    func rect(at timeSeconds: TimeInterval) -> NormalizedVideoRect? {
        guard isEnabled, isActive(at: timeSeconds) else { return nil }
        return keyframedRect(at: timeSeconds)
    }

    /// Returns the interpolated keyframe value even when the track is outside
    /// its visible range. The editor uses this when extending an existing mask
    /// to a new start or end frame.
    func keyframedRect(at timeSeconds: TimeInterval) -> NormalizedVideoRect? {
        let ordered = Self.ordered(keyframes)
        guard let first = ordered.first else { return nil }
        guard ordered.count > 1 else { return first.rect }

        let time = timeSeconds.isFinite ? max(0, timeSeconds) : 0
        if time <= first.timeSeconds {
            return first.rect
        }
        guard let last = ordered.last, time < last.timeSeconds else {
            return ordered.last?.rect
        }

        guard let nextIndex = ordered.firstIndex(where: { $0.timeSeconds >= time }),
              nextIndex > 0 else {
            return first.rect
        }
        let previous = ordered[nextIndex - 1]
        let next = ordered[nextIndex]
        let duration = next.timeSeconds - previous.timeSeconds
        guard duration > 0 else { return next.rect }
        return NormalizedVideoRect.interpolate(
            from: previous.rect,
            to: next.rect,
            progress: (time - previous.timeSeconds) / duration
        )
    }

    private func isActive(at timeSeconds: TimeInterval) -> Bool {
        let time = timeSeconds.isFinite ? max(0, timeSeconds) : 0
        if let activeFromSeconds, time < activeFromSeconds {
            return false
        }
        if let activeUntilSeconds, time > activeUntilSeconds {
            return false
        }
        return true
    }

    private static func ordered(_ keyframes: [MaskKeyframe]) -> [MaskKeyframe] {
        keyframes.sorted {
            if $0.timeSeconds == $1.timeSeconds {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.timeSeconds < $1.timeSeconds
        }
    }

    private static func validOptionalTime(
        _ value: TimeInterval?
    ) -> TimeInterval? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }
}

#if DEBUG
enum MaskTrackSmoke {
    static func run() {
        let firstRect = NormalizedVideoRect(
            x: 0.1,
            y: 0.2,
            width: 0.2,
            height: 0.25
        )
        let secondRect = NormalizedVideoRect(
            x: 0.5,
            y: 0.4,
            width: 0.2,
            height: 0.25
        )
        var track = MaskTrack(
            shape: .ellipse,
            source: .detectedFace,
            trackingState: .lost,
            trackingLostAtSeconds: 2,
            keyframes: [
                MaskKeyframe(timeSeconds: 0, rect: firstRect),
                MaskKeyframe(
                    timeSeconds: 2,
                    rect: secondRect,
                    origin: .automaticTracking
                ),
            ]
        )

        // A loss holds the last known box for privacy until the user corrects
        // it, rather than silently exposing the remainder of the clip.
        precondition(track.rect(at: 4) == secondRect)
        track.markManualCorrection(at: 1)
        precondition(track.trackingState == .lost)
        track.setKeyframe(MaskKeyframe(timeSeconds: 3, rect: firstRect))
        track.markManualCorrection(at: 3)
        precondition(track.trackingState == .needsRetracking)
        precondition(track.trackingLostAtSeconds == nil)

        track.removeKeyframes(after: 3)
        track.applyTrackingResult(
            keyframes: [
                MaskKeyframe(
                    timeSeconds: 4,
                    rect: secondRect,
                    origin: .automaticTracking
                ),
            ],
            lostAtSeconds: nil
        )
        precondition(track.trackingState == .tracked)
        precondition(track.rect(at: 4) == secondRect)
    }
}
#endif
