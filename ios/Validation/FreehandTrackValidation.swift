import Foundation

@main
struct FreehandTrackValidation {
    static func main() throws {
        let path = NormalizedMaskPath(points: [.init(x: 0.2, y: 0.3), .init(x: 0.4, y: 0.5)], strokeWidth: 0.08)!
        var track = MaskTrack(shape: .rectangle, manualPath: path,
                              keyframes: [.init(timeSeconds: 0, rect: path.boundingRect)])
        precondition(track.path(at: 180) == path)
        track.updateManualRect(.init(x: 0.5, y: 0.1, width: 0.2, height: 0.2), at: 60)
        let moved = track.path(at: 60)!
        precondition(abs(moved.points[0].x - 0.5) < 1e-8)
        precondition(abs(moved.points[1].y - 0.3) < 1e-8)
        track.updateManualRect(.init(x: 0.1, y: 0.5, width: 0.4, height: 0.4), at: 10)
        let middle = track.path(at: 5)!
        precondition(abs(middle.points[0].x - 0.15) < 1e-8)
        precondition(abs(middle.strokeWidth - 0.12) < 1e-8)
        track.activeFromSeconds = 2
        track.activeUntilSeconds = 8
        precondition(track.path(at: 1) == nil && track.path(at: 9) == nil)
        let restored = try JSONDecoder().decode(MaskTrack.self, from: JSONEncoder().encode(track))
        precondition(restored == track && restored.path(at: 5) == middle)
        let dot = NormalizedMaskPath(points: [.init(x: 1, y: 0)], strokeWidth: 0.08)!
        let dotTrack = MaskTrack(shape: .rectangle, manualPath: dot,
                                 keyframes: [.init(timeSeconds: 0, rect: dot.boundingRect)])
        precondition(dotTrack.path(at: 0) != nil)
        print("PASS: brush single-position hold, automatic keyframes, translation, scaling, time bounds, Codable, edge dot")
    }
}
