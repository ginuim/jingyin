import Foundation

@main
struct MaskTrackValidation {
    static func main() throws {
        let first = NormalizedVideoRect(x: 0.1, y: 0.2, width: 0.15, height: 0.25)
        let last = NormalizedVideoRect(x: 0.6, y: 0.4, width: 0.2, height: 0.3)
        assertRect(
            first.rect(inPreviewBounds: CGRect(x: 20, y: 40, width: 200, height: 400)),
            equals: CGRect(x: 40, y: 120, width: 30, height: 100)
        )
        assertRect(
            first.rect(inCoreImageExtent: CGRect(x: 0, y: 0, width: 200, height: 400)),
            equals: CGRect(x: 20, y: 220, width: 30, height: 100)
        )
        assertRect(
            NormalizedVideoRect(visionBoundingBox: first.visionBoundingBox).cgRect,
            equals: first.cgRect
        )
        var track = MaskTrack(shape: .rectangle, keyframes: [.init(timeSeconds: 9, rect: first)])
        precondition(track.rect(at: 0) == first && track.rect(at: 100) == first)
        track.updateManualRect(last, at: 15)
        precondition(track.keyframes.count == 2)
        precondition(track.rect(at: 0) == first && track.rect(at: 100) == last)
        precondition(
            track.rect(at: 12)
                == NormalizedVideoRect.interpolate(from: first, to: last, progress: 0.5)
        )
        track.updateManualRect(first, at: 15)
        precondition(track.keyframes.count == 2 && track.rect(at: 15) == first)
        let records = track.keyframes
        track.activeFromSeconds = 2
        track.activeUntilSeconds = 12
        precondition(track.rect(at: 1) == nil && track.rect(at: 13) == nil)
        precondition(track.keyframes == records)

        var legacy = MaskTrack(
            shape: .ellipse,
            keyframes: [.init(timeSeconds: 0, rect: first), .init(timeSeconds: 10, rect: last)]
        )
        let encoded = try JSONEncoder().encode(legacy)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json["manualPositionMode"] = "fixed"
        legacy = try JSONDecoder().decode(MaskTrack.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(legacy.rect(at: 5) == NormalizedVideoRect.interpolate(from: first, to: last, progress: 0.5))
        legacy.updateManualRect(last, at: 10)
        precondition(legacy.keyframes.count == 2)
        let restored = try JSONDecoder().decode(MaskTrack.self, from: JSONEncoder().encode(track))
        precondition(restored == track)
        let original = legacy
        legacy.source = .detectedFace
        legacy.updateManualRect(first, at: 5)
        precondition(legacy.keyframes.count == 3)
        precondition(original.rect(at: 100) == last)
        print("PASS: preview/export coordinates, Vision round trip, single-position hold, automatic interpolation, active bounds, legacy decoding, same-time replacement, Codable round trip")
    }

    private static func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000_001
    ) {
        precondition(abs(actual.minX - expected.minX) <= accuracy)
        precondition(abs(actual.minY - expected.minY) <= accuracy)
        precondition(abs(actual.width - expected.width) <= accuracy)
        precondition(abs(actual.height - expected.height) <= accuracy)
    }
}
