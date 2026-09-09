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
        var fixed = MaskTrack(shape: .rectangle, keyframes: [.init(timeSeconds: 9, rect: first)])
        fixed.updateManualRect(last, at: 15)
        precondition(fixed.rect(at: 0) == last && fixed.rect(at: 100) == last)
        precondition(fixed.keyframes.count == 1)
        fixed.setPositionMode(.animated, at: 3)
        fixed.updateManualRect(first, at: 9)
        precondition(fixed.rect(at: 0) == last && fixed.rect(at: 20) == first)
        precondition(fixed.rect(at: 6) == NormalizedVideoRect.interpolate(from: last, to: first, progress: 0.5))
        let records = fixed.keyframes
        fixed.activeFromSeconds = 2
        fixed.activeUntilSeconds = 12
        precondition(fixed.rect(at: 1) == nil && fixed.rect(at: 13) == nil)
        precondition(fixed.keyframes == records)
        let current = fixed.keyframedRect(at: 6)!
        fixed.setPositionMode(.fixed, at: 6)
        precondition(fixed.rect(at: 3) == current && fixed.rect(at: 11) == current)
        var legacy = MaskTrack(shape: .ellipse, keyframes: [.init(timeSeconds: 0, rect: first), .init(timeSeconds: 10, rect: last)])
        let encoded = try JSONEncoder().encode(legacy)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "manualPositionMode")
        legacy = try JSONDecoder().decode(MaskTrack.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(legacy.effectivePositionMode == .animated)
        precondition(legacy.rect(at: 5) == NormalizedVideoRect.interpolate(from: first, to: last, progress: 0.5))
        legacy.updateManualRect(last, at: 10)
        precondition(legacy.keyframes.count == 2)
        let restored = try JSONDecoder().decode(MaskTrack.self, from: JSONEncoder().encode(fixed))
        precondition(restored == fixed)
        let original = legacy
        legacy.source = .detectedFace
        let tracked = legacy
        legacy.setPositionMode(.fixed, at: 5)
        precondition(legacy == tracked)
        precondition(original.rect(at: 100) == last)
        print("PASS: preview/export coordinates, Vision round trip, fixed interval, interpolation, active bounds, mode conversion, legacy decoding, same-time replacement, Codable round trip, tracking preservation")
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
