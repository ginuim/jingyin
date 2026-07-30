import CoreImage
import Photos
import UIKit
import Vision

enum PhotoWorkStatus: Equatable {
    case pending
    case analyzing
    case ready
    case exporting
    case completed
    case failed
}

struct PhotoDraft: Identifiable {
    let id: UUID
    let inputURL: URL
    var previewImage: UIImage?
    var displaySize: CGSize?
    var tracks: [MaskTrack]
    var status: PhotoWorkStatus
    var outputURL: URL?

    init(id: UUID = UUID(), inputURL: URL) {
        self.id = id
        self.inputURL = inputURL
        previewImage = nil
        displaySize = nil
        tracks = []
        status = .pending
        outputURL = nil
    }
}

struct PhotoAnalysis: @unchecked Sendable {
    let previewImage: UIImage
    let displaySize: CGSize
    let tracks: [MaskTrack]
}

struct RenderedPhoto: @unchecked Sendable {
    let image: UIImage
}

enum PhotoProcessor {
    enum ProcessingError: Error {
        case invalidImage
        case renderFailed
        case photoAccessDenied
    }

    static func analyze(
        url: URL,
        subjects: Set<SubjectKind>
    ) async throws -> PhotoAnalysis {
        try await Task.detached(priority: .userInitiated) {
            guard let source = orientedImage(at: url) else {
                throw ProcessingError.invalidImage
            }
            let preview = try makePreview(from: source)
            let tracks = detectTracks(in: source, subjects: subjects)
            return PhotoAnalysis(
                previewImage: preview.image,
                displaySize: preview.image.size,
                tracks: tracks
            )
        }.value
    }

    static func renderPreview(
        url: URL,
        options: ProcessingOptions
    ) async throws -> RenderedPhoto {
        try await Task.detached(priority: .userInitiated) {
            guard let source = orientedImage(at: url) else {
                throw ProcessingError.invalidImage
            }
            let preview = try makePreview(from: source)
            let rendered = FrameEffectProcessor(options: options).render(preview.ciImage)
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let cgImage = context.createCGImage(rendered, from: rendered.extent) else {
                throw ProcessingError.renderFailed
            }
            return RenderedPhoto(image: UIImage(cgImage: cgImage))
        }.value
    }

    /// Enforces the free single-photo boundary in the processing layer, even
    /// when a caller accidentally supplies a larger batch.
    static func export(
        drafts: [PhotoDraft],
        options: ProcessingOptions,
        access: ExportAccess
    ) async -> [PhotoDraft.ID: Result<URL, Error>] {
        let allowed = access == .free ? Array(drafts.prefix(1)) : drafts
        var results: [PhotoDraft.ID: Result<URL, Error>] = [:]
        for draft in allowed {
            if Task.isCancelled { break }
            do {
                let output = try await exportOne(
                    inputURL: draft.inputURL,
                    options: optionsForExport(options, tracks: draft.tracks)
                )
                results[draft.id] = .success(output)
            } catch {
                results[draft.id] = .failure(error)
            }
        }
        return results
    }

    static func saveToPhotos(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ProcessingError.photoAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            for url in urls {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        }
    }

    static func removeOutputs(from drafts: [PhotoDraft]) {
        for draft in drafts {
            guard let outputURL = draft.outputURL else { continue }
            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    static func optionsForExport(
        _ options: ProcessingOptions,
        tracks: [MaskTrack]
    ) -> ProcessingOptions {
        var result = options
        // Automatic detections have already been materialized as independent,
        // editable tracks. Do not run a second combined subject detector here.
        result.subjects = []
        result.maskTracks = tracks
        return result
    }

    private static func exportOne(
        inputURL: URL,
        options: ProcessingOptions
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let source = orientedImage(at: inputURL) else {
                throw ProcessingError.invalidImage
            }
            let rendered = FrameEffectProcessor(options: options).render(source)
            let context = CIContext(options: [.cacheIntermediates: false])
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("jingyin-photo-output-\(UUID().uuidString)")
                .appendingPathExtension("jpg")
            do {
                try context.writeJPEGRepresentation(
                    of: rendered,
                    to: output,
                    colorSpace: colorSpace,
                    options: [
                        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
                    ]
                )
                return output
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw error
            }
        }.value
    }

    private static func orientedImage(at url: URL) -> CIImage? {
        guard let image = CIImage(
            contentsOf: url,
            options: [.applyOrientationProperty: true]
        ) else {
            return nil
        }
        return image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            )
        )
    }

    private static func makePreview(
        from source: CIImage
    ) throws -> (image: UIImage, ciImage: CIImage) {
        let maximumEdge: CGFloat = 1600
        let longest = max(source.extent.width, source.extent.height)
        let scale = longest > maximumEdge ? maximumEdge / longest : 1
        let preview = source
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(preview, from: preview.extent) else {
            throw ProcessingError.renderFailed
        }
        return (UIImage(cgImage: cgImage), preview)
    }

    private static func detectTracks(
        in image: CIImage,
        subjects: Set<SubjectKind>
    ) -> [MaskTrack] {
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false
        let faceRequest = VNDetectFaceRectanglesRequest()
        let animalRequest = VNRecognizeAnimalsRequest()

        let requests: [VNRequest] = [
            subjects.contains(.person) ? humanRequest : nil,
            subjects.contains(.face) ? faceRequest : nil,
            subjects.contains(.pet) ? animalRequest : nil
        ].compactMap { $0 }
        guard !requests.isEmpty else { return [] }

        for request in requests {
            configureCPU(request)
            // One unsupported request must not make the whole photo unreadable.
            // It produces zero groups for that subject and leaves manual masks
            // available as a privacy-safe fallback.
            try? VNImageRequestHandler(ciImage: image, orientation: .up)
                .perform([request])
        }

        var candidates: [(rect: NormalizedVideoRect, shape: MaskTrackShape, source: MaskTrackSource)] = []
        if subjects.contains(.person) {
            candidates += (humanRequest.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map {
                    (
                        padded(
                            NormalizedVideoRect(visionBoundingBox: $0.boundingBox),
                            horizontal: 0.06,
                            vertical: 0.04
                        ),
                        .rectangle,
                        .detectedPerson
                    )
                }
        }
        if subjects.contains(.face) {
            candidates += (faceRequest.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map {
                    (
                        NormalizedVideoRect(visionBoundingBox: $0.boundingBox)
                            .expandedForFaceCoverage(),
                        .ellipse,
                        .detectedFace
                    )
                }
        }
        if subjects.contains(.pet) {
            candidates += (animalRequest.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map {
                    (
                        padded(
                            NormalizedVideoRect(visionBoundingBox: $0.boundingBox),
                            horizontal: 0.06,
                            vertical: 0.06
                        ),
                        .rectangle,
                        .detectedPet
                    )
                }
        }

        var accepted: [(NormalizedVideoRect, MaskTrackShape, MaskTrackSource)] = []
        for candidate in candidates.sorted(by: {
            $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height
        }) {
            let duplicate = accepted.contains {
                $0.2 == candidate.source
                    && intersectionOverUnion($0.0.cgRect, candidate.rect.cgRect) >= 0.65
            }
            if !duplicate {
                accepted.append((candidate.rect, candidate.shape, candidate.source))
            }
        }
        return accepted.map { rect, shape, source in
            MaskTrack(
                shape: shape,
                source: source,
                keyframes: [MaskKeyframe(timeSeconds: 0, rect: rect)]
            )
        }
    }

    private static func configureCPU(_ request: VNRequest) {
        guard let stages = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stages {
            guard let cpu = devices.first(where: {
                if case .cpu = $0 { return true }
                return false
            }) else {
                continue
            }
            request.setComputeDevice(cpu, for: stage)
        }
    }

    private static func padded(
        _ rect: NormalizedVideoRect,
        horizontal: Double,
        vertical: Double
    ) -> NormalizedVideoRect {
        let dx = rect.width * horizontal
        let dy = rect.height * vertical
        return NormalizedVideoRect(
            x: max(0, rect.x - dx),
            y: max(0, rect.y - dy),
            width: min(1, rect.width + dx * 2),
            height: min(1, rect.height + dy * 2)
        )
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }
        let area = intersection.width * intersection.height
        let union = lhs.width * lhs.height + rhs.width * rhs.height - area
        return union > 0 ? Double(area / union) : 0
    }
}
