import CoreGraphics
import Foundation

enum MaskEntityAssociation {
    static let iouThreshold = 0.3

    struct Detection: Equatable, Sendable {
        var kind: SubjectKind
        var source: MaskTrackSource
        var rect: NormalizedVideoRect
    }

    /// Match frame detections to existing entities by kind + IoU.
    /// Disabled entities that leave the frame are retained so scrubbing can
    /// re-associate without clearing the user's off switch.
    static func associate(
        existing: [MaskEntity],
        detections: [Detection]
    ) -> [MaskEntity] {
        var result: [MaskEntity] = []
        var usedExisting = Set<UUID>()

        for detection in detections {
            var bestID: UUID?
            var bestIoU = iouThreshold
            for entity in existing {
                guard entity.kind == detection.kind,
                      !usedExisting.contains(entity.id) else { continue }
                let score = iou(entity.lastRect, detection.rect)
                if score >= bestIoU {
                    bestIoU = score
                    bestID = entity.id
                }
            }

            if let bestID,
               let matched = existing.first(where: { $0.id == bestID }) {
                usedExisting.insert(matched.id)
                result.append(
                    MaskEntity(
                        id: matched.id,
                        kind: detection.kind,
                        source: detection.source,
                        isEnabled: matched.isEnabled,
                        lastRect: detection.rect
                    )
                )
            } else {
                result.append(
                    MaskEntity(
                        kind: detection.kind,
                        source: detection.source,
                        lastRect: detection.rect
                    )
                )
            }
        }

        for entity in existing where !usedExisting.contains(entity.id) && !entity.isEnabled {
            if !result.contains(where: { $0.id == entity.id }) {
                result.append(entity)
            }
        }
        return result
    }

    static func iou(_ a: NormalizedVideoRect, _ b: NormalizedVideoRect) -> Double {
        let ar = a.cgRect
        let br = b.cgRect
        let inter = ar.intersection(br)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let union = ar.width * ar.height + br.width * br.height - interArea
        guard union > 0 else { return 0 }
        return Double(interArea / union)
    }
}
