@preconcurrency import AVFoundation
import UIKit
@preconcurrency import Vision

struct DetectedFaceCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let visionBoundingBox: CGRect

    init(id: UUID = UUID(), visionBoundingBox: CGRect) {
        self.id = id
        self.visionBoundingBox = visionBoundingBox
    }

    var displayRect: NormalizedVideoRect {
        NormalizedVideoRect(visionBoundingBox: visionBoundingBox)
    }

    var coverageRect: NormalizedVideoRect {
        displayRect.expandedForFaceCoverage()
    }
}

struct FaceDetectionSnapshot: Sendable {
    let previewJPEGData: Data
    let displaySize: CGSize
    let actualTimeSeconds: TimeInterval
    let candidates: [DetectedFaceCandidate]
}

struct FaceTrackingResult: Sendable {
    let keyframes: [MaskKeyframe]
    let lostAtSeconds: TimeInterval?
}

enum FaceTrackingError: Error {
    case invalidVideo
    case previewUnavailable
}

enum FaceTrackingService {
    static func detectFaces(
        in videoURL: URL,
        at timeSeconds: TimeInterval
    ) async throws -> FaceDetectionSnapshot {
        let asset = AVURLAsset(url: videoURL)
        guard try await asset.loadTracks(withMediaType: .video).first != nil else {
            throw FaceTrackingError.invalidVideo
        }
        let generator = makeImageGenerator(asset: asset)
        let requestedTime = CMTime(
            seconds: max(0, timeSeconds.isFinite ? timeSeconds : 0),
            preferredTimescale: 600
        )
        let result = try await generator.image(at: requestedTime)
        try Task.checkCancellation()

        let request = VNDetectFaceRectanglesRequest()
        preferCPUCompute(for: request)
        let handler = VNImageRequestHandler(cgImage: result.image, orientation: .up)
        try handler.perform([request])
        let candidates = (request.results ?? [])
            .filter { $0.confidence >= 0.35 }
            .sorted {
                if abs($0.boundingBox.midX - $1.boundingBox.midX) > 0.02 {
                    return $0.boundingBox.midX < $1.boundingBox.midX
                }
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            .map { DetectedFaceCandidate(visionBoundingBox: $0.boundingBox) }

        guard let data = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.88) else {
            throw FaceTrackingError.previewUnavailable
        }
        return FaceDetectionSnapshot(
            previewJPEGData: data,
            displaySize: CGSize(
                width: result.image.width,
                height: result.image.height
            ),
            actualTimeSeconds: result.actualTime.seconds.isFinite
                ? result.actualTime.seconds
                : max(0, timeSeconds),
            candidates: candidates
        )
    }

    static func trackFace(
        in videoURL: URL,
        from startTimeSeconds: TimeInterval,
        initialVisionBoundingBox: CGRect
    ) async throws -> FaceTrackingResult {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw FaceTrackingError.invalidVideo
        }

        let start = min(max(startTimeSeconds, 0), duration)
        let remaining = max(0, duration - start)
        guard remaining > 1.0 / 60.0 else {
            return FaceTrackingResult(keyframes: [], lostAtSeconds: nil)
        }

        // Keep enough temporal density for smooth interpolation while bounding
        // a five-minute clip to roughly 900 Vision tracking requests.
        let sampleInterval = max(
            remaining > 120 ? 0.5 : 0.25,
            remaining / 900
        )
        let generator = makeImageGenerator(asset: asset)
        let sequenceHandler = VNSequenceRequestHandler()
        var observation = VNDetectedObjectObservation(
            boundingBox: initialVisionBoundingBox
        )
        var keyframes: [MaskKeyframe] = []
        var sampleTime = start + sampleInterval

        while sampleTime <= duration + 1.0 / 600.0 {
            try Task.checkCancellation()
            let requestedTime = CMTime(
                seconds: min(sampleTime, duration),
                preferredTimescale: 600
            )
            let frame: (image: CGImage, actualTime: CMTime)
            do {
                frame = try await generator.image(at: requestedTime)
            } catch {
                return FaceTrackingResult(
                    keyframes: keyframes,
                    lostAtSeconds: min(sampleTime, duration)
                )
            }
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            preferCPUCompute(for: request)

            do {
                try sequenceHandler.perform([request], on: frame.image)
            } catch {
                return FaceTrackingResult(
                    keyframes: keyframes,
                    lostAtSeconds: frame.actualTime.seconds
                )
            }

            guard let tracked = request.results?.first as? VNDetectedObjectObservation,
                  tracked.confidence >= 0.32,
                  !tracked.boundingBox.isNull,
                  tracked.boundingBox.width >= 0.015,
                  tracked.boundingBox.height >= 0.015 else {
                return FaceTrackingResult(
                    keyframes: keyframes,
                    lostAtSeconds: frame.actualTime.seconds
                )
            }

            observation = tracked
            let actualTime = frame.actualTime.seconds.isFinite
                ? max(start, frame.actualTime.seconds)
                : min(sampleTime, duration)
            keyframes.append(
                MaskKeyframe(
                    timeSeconds: actualTime,
                    rect: NormalizedVideoRect(
                        visionBoundingBox: tracked.boundingBox
                    ).expandedForFaceCoverage(),
                    origin: .automaticTracking
                )
            )

            if sampleTime >= duration {
                break
            }
            sampleTime = min(sampleTime + sampleInterval, duration)
        }

        return FaceTrackingResult(keyframes: keyframes, lostAtSeconds: nil)
    }

    private static func makeImageGenerator(
        asset: AVAsset
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: 1.0 / 60.0,
            preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 1.0 / 60.0,
            preferredTimescale: 600
        )
        return generator
    }

    private static func preferCPUCompute(for request: VNRequest) {
        guard let stageDevices = try? request.supportedComputeStageDevices else {
            return
        }
        for (stage, devices) in stageDevices {
            guard let cpu = devices.first(where: { device in
                if case .cpu = device { return true }
                return false
            }) else {
                continue
            }
            request.setComputeDevice(cpu, for: stage)
        }
    }
}
