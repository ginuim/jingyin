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

/// One low-resolution label map can serve every entity produced by the same
/// Vision request. Groups keep only an instance number instead of duplicating
/// a full-size alpha mask for every person or animal.
struct PhotoMaskPlane: Identifiable, Hashable, Sendable {
    let id: UUID
    let width: Int
    let height: Int
    let labels: Data

    init(
        id: UUID = UUID(),
        width: Int,
        height: Int,
        labels: Data
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.labels = labels
    }

    func normalizedBounds(
        for label: UInt16,
        trimmingOutliers fraction: Double = 0
    ) -> NormalizedVideoRect? {
        guard label > 0, width > 0, height > 0 else { return nil }
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        var xCounts = [Int](repeating: 0, count: width)
        var yCounts = [Int](repeating: 0, count: height)
        var total = 0
        labels.withUnsafeBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: UInt16.self)
            guard values.count >= width * height else { return }
            for y in 0..<height {
                for x in 0..<width where values[y * width + x] == label {
                    minimumX = min(minimumX, x)
                    minimumY = min(minimumY, y)
                    maximumX = max(maximumX, x)
                    maximumY = max(maximumY, y)
                    xCounts[x] += 1
                    yCounts[y] += 1
                    total += 1
                }
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        let safeFraction = min(max(fraction, 0), 0.1)
        let trimCount = total >= 400
            ? max(1, Int(Double(total) * safeFraction))
            : 0
        if trimCount > 0 {
            minimumX = trimmedLowerBound(in: xCounts, removing: trimCount)
            maximumX = trimmedUpperBound(in: xCounts, removing: trimCount)
            minimumY = trimmedLowerBound(in: yCounts, removing: trimCount)
            maximumY = trimmedUpperBound(in: yCounts, removing: trimCount)
        }
        return NormalizedVideoRect(
            x: Double(minimumX) / Double(width),
            y: Double(minimumY) / Double(height),
            width: Double(maximumX - minimumX + 1) / Double(width),
            height: Double(maximumY - minimumY + 1) / Double(height)
        )
    }

    private func trimmedLowerBound(
        in counts: [Int],
        removing target: Int
    ) -> Int {
        var removed = 0
        for index in counts.indices {
            if removed + counts[index] > target {
                return index
            }
            removed += counts[index]
        }
        return counts.startIndex
    }

    private func trimmedUpperBound(
        in counts: [Int],
        removing target: Int
    ) -> Int {
        var removed = 0
        for index in counts.indices.reversed() {
            if removed + counts[index] > target {
                return index
            }
            removed += counts[index]
        }
        return counts.index(before: counts.endIndex)
    }

    func coverage(for label: UInt16) -> Double {
        guard label > 0, width > 0, height > 0 else { return 0 }
        var matchingPixels = 0
        labels.withUnsafeBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: UInt16.self)
            guard values.count >= width * height else { return }
            for value in values.prefix(width * height) where value == label {
                matchingPixels += 1
            }
        }
        return Double(matchingPixels) / Double(width * height)
    }
}

struct PhotoMaskGroup: Identifiable, Hashable, Sendable {
    var track: MaskTrack
    let maskPlaneID: PhotoMaskPlane.ID?
    let instanceLabel: UInt16?
    let originalRect: NormalizedVideoRect

    var id: MaskTrack.ID { track.id }
    var hasEdgeMask: Bool {
        maskPlaneID != nil && instanceLabel != nil
    }

    init(
        track: MaskTrack,
        maskPlaneID: PhotoMaskPlane.ID? = nil,
        instanceLabel: UInt16? = nil,
        originalRect: NormalizedVideoRect? = nil
    ) {
        self.track = track
        self.maskPlaneID = maskPlaneID
        self.instanceLabel = instanceLabel
        self.originalRect = originalRect
            ?? track.keyframedRect(at: 0)
            ?? NormalizedVideoRect(x: 0, y: 0, width: 0, height: 0)
    }
}

struct PhotoDraft: Identifiable {
    let id: UUID
    let inputURL: URL
    var previewImage: UIImage?
    var displaySize: CGSize?
    var maskGroups: [PhotoMaskGroup]
    var maskPlanes: [PhotoMaskPlane]
    var status: PhotoWorkStatus
    var outputURL: URL?

    init(id: UUID = UUID(), inputURL: URL) {
        self.id = id
        self.inputURL = inputURL
        previewImage = nil
        displaySize = nil
        maskGroups = []
        maskPlanes = []
        status = .pending
        outputURL = nil
    }
}

struct PhotoAnalysis: @unchecked Sendable {
    let previewImage: UIImage
    let displaySize: CGSize
    let maskGroups: [PhotoMaskGroup]
    let maskPlanes: [PhotoMaskPlane]
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

    #if DEBUG
    static func runSmokeTests() {
        let labels: [UInt16] = [
            1, 1, 0, 2,
            1, 0, 2, 2
        ]
        let plane = labels.withUnsafeBytes {
            PhotoMaskPlane(
                width: 4,
                height: 2,
                labels: Data($0)
            )
        }
        precondition(
            plane.normalizedBounds(for: 1)?.cgRect
                == CGRect(x: 0, y: 0, width: 0.5, height: 1)
        )
        precondition(
            plane.normalizedBounds(for: 2)?.cgRect
                == CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        )
        precondition(abs(plane.coverage(for: 1) - 0.375) < 0.0001)
        precondition(abs(plane.coverage(for: 2) - 0.375) < 0.0001)
        let firstTrack = MaskTrack(
            shape: .rectangle,
            source: .detectedPerson,
            keyframes: [
                MaskKeyframe(
                    timeSeconds: 0,
                    rect: NormalizedVideoRect(
                        x: 0,
                        y: 0,
                        width: 0.5,
                        height: 1
                    )
                )
            ]
        )
        let group = PhotoMaskGroup(
            track: firstTrack,
            maskPlaneID: plane.id,
            instanceLabel: 1
        )
        precondition(group.hasEdgeMask)
        precondition(
            optionsForPhoto(
                ProcessingOptions(),
                maskGroups: [group]
            ).maskTracks.isEmpty
        )
        let secondTrack = MaskTrack(
            shape: .rectangle,
            source: .detectedPerson,
            keyframes: [
                MaskKeyframe(
                    timeSeconds: 0,
                    rect: NormalizedVideoRect(
                        x: 0.5,
                        y: 0,
                        width: 0.5,
                        height: 1
                    )
                )
            ]
        )
        let secondGroup = PhotoMaskGroup(
            track: secondTrack,
            maskPlaneID: plane.id,
            instanceLabel: 2
        )
        let extent = CGRect(x: 0, y: 0, width: 40, height: 20)
        guard let firstOnlyMask = combinedEdgeMask(
            groups: [group],
            planes: [plane],
            extent: extent
        ) else {
            preconditionFailure("Expected an independent raster mask")
        }
        var pixels = [UInt8](repeating: 0, count: 40 * 20 * 4)
        CIContext().render(
            firstOnlyMask,
            toBitmap: &pixels,
            rowBytes: 40 * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        precondition(pixels[(10 * 40 + 5) * 4] > 200)
        precondition(pixels[(10 * 40 + 35) * 4] < 10)
        precondition(
            combinedEdgeMask(
                groups: [group, secondGroup],
                planes: [plane],
                extent: extent
            ) != nil
        )
    }
    #endif

    static func analyze(
        url: URL,
        subjects: Set<SubjectKind>
    ) async throws -> PhotoAnalysis {
        try await Task.detached(priority: .userInitiated) {
            guard let source = orientedImage(at: url) else {
                throw ProcessingError.invalidImage
            }
            let preview = try makePreview(from: source)
            let detection = detectMaskGroups(in: source, subjects: subjects)
            return PhotoAnalysis(
                previewImage: preview.image,
                displaySize: preview.image.size,
                maskGroups: detection.groups,
                maskPlanes: detection.planes
            )
        }.value
    }

    static func renderPreview(
        url: URL,
        options: ProcessingOptions,
        maskGroups: [PhotoMaskGroup],
        maskPlanes: [PhotoMaskPlane]
    ) async throws -> RenderedPhoto {
        try await Task.detached(priority: .userInitiated) {
            guard let source = orientedImage(at: url) else {
                throw ProcessingError.invalidImage
            }
            let preview = try makePreview(from: source)
            let rendered = render(
                preview.ciImage,
                options: options,
                maskGroups: maskGroups,
                maskPlanes: maskPlanes
            )
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
                    options: options,
                    maskGroups: draft.maskGroups,
                    maskPlanes: draft.maskPlanes
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

    static func optionsForPhoto(
        _ options: ProcessingOptions,
        maskGroups: [PhotoMaskGroup]
    ) -> ProcessingOptions {
        var result = options
        result.stickerFaceRects = maskGroups.compactMap { group in
            guard group.track.source == .detectedFace || group.track.source == .manual else {
                return nil
            }
            return group.track.rect(at: 0) ?? group.originalRect
        }
        // Automatic detections have already been materialized as independent
        // raster groups. Only manual/fallback geometry stays in MaskTrack.
        result.subjects = []
        result.maskTracks = maskGroups
            .filter { !$0.hasEdgeMask }
            .map(\.track)
        return result
    }

    private static func exportOne(
        inputURL: URL,
        options: ProcessingOptions,
        maskGroups: [PhotoMaskGroup],
        maskPlanes: [PhotoMaskPlane]
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let source = orientedImage(at: inputURL) else {
                throw ProcessingError.invalidImage
            }
            let rendered = render(
                source,
                options: options,
                maskGroups: maskGroups,
                maskPlanes: maskPlanes
            )
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

    private static func render(
        _ source: CIImage,
        options: ProcessingOptions,
        maskGroups: [PhotoMaskGroup],
        maskPlanes: [PhotoMaskPlane]
    ) -> CIImage {
        let photoOptions = optionsForPhoto(options, maskGroups: maskGroups)
        let edgeMask = combinedEdgeMask(
            groups: maskGroups,
            planes: maskPlanes,
            extent: source.extent
        )
        return FrameEffectProcessor(options: photoOptions).render(
            source,
            externalMask: edgeMask
        )
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

    private static func detectMaskGroups(
        in image: CIImage,
        subjects: Set<SubjectKind>
    ) -> (groups: [PhotoMaskGroup], planes: [PhotoMaskPlane]) {
        var groups: [PhotoMaskGroup] = []
        var planes: [PhotoMaskPlane] = []

        if subjects.contains(.person) {
            let people = personGroups(in: image)
            groups += people.groups
            if let plane = people.plane {
                planes.append(plane)
            }
        }

        guard subjects.contains(.face) || subjects.contains(.pet) else {
            return (groups, planes)
        }

        let foreground = foregroundInstances(in: image)
        if let plane = foreground?.plane {
            planes.append(plane)
        }
        if subjects.contains(.face) {
            groups += faceGroups(in: image, foreground: foreground)
        }
        if subjects.contains(.pet) {
            groups += petGroups(in: image, foreground: foreground)
        }
        return (groups, planes)
    }

    private static func personGroups(
        in image: CIImage
    ) -> (groups: [PhotoMaskGroup], plane: PhotoMaskPlane?) {
        let request = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        if (try? handler.perform([request])) != nil,
           let observation = request.results?.first,
           let rawPlane = makeMaskPlane(from: observation.instanceMask) {
            // Person-instance masks can occasionally promote a large salient
            // foreground region (blanket, furniture, etc.) to the person's
            // instance. Intersecting it with the independent semantic person
            // request keeps the instance identity while removing non-person
            // foreground pixels.
            let plane: PhotoMaskPlane?
            if let personMask = semanticPersonMask(in: image) {
                // If semantic validation succeeds but produces no overlap, the
                // instance is invalid. Do not revive the unvalidated full-frame
                // label through a nil-coalescing fallback.
                plane = intersect(rawPlane, withPersonMask: personMask)
            } else {
                plane = rawPlane
            }
            let groups = plane.map { plane in
                observation.allInstances.compactMap { instance -> PhotoMaskGroup? in
                guard instance > 0,
                      instance <= Int(UInt16.max),
                      let rect = plane.normalizedBounds(
                        for: UInt16(instance),
                        trimmingOutliers: 0.005
                      ),
                      plane.coverage(for: UInt16(instance)) <= 0.88,
                      rect.width * rect.height <= 0.95 else {
                    return nil
                }
                let track = MaskTrack(
                    shape: .rectangle,
                    source: .detectedPerson,
                    keyframes: [MaskKeyframe(timeSeconds: 0, rect: rect)]
                )
                return PhotoMaskGroup(
                    track: track,
                    maskPlaneID: plane.id,
                    instanceLabel: UInt16(instance),
                    originalRect: rect
                )
                }
            } ?? []
            if let plane, !groups.isEmpty {
                return (groups, plane)
            }
        }

        // Privacy-safe geometric fallback for devices or images where instance
        // segmentation is unavailable.
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let faces = VNDetectFaceRectanglesRequest()
        configureCPU(humans)
        configureCPU(faces)
        try? VNImageRequestHandler(ciImage: image, orientation: .up)
            .perform([humans, faces])
        let humanRects = (humans.results ?? [])
            .filter { $0.confidence >= 0.35 }
            .map {
                padded(
                    NormalizedVideoRect(visionBoundingBox: $0.boundingBox),
                    horizontal: 0.025,
                    vertical: 0.025
                )
            }
        if !humanRects.isEmpty {
            return (
                deduplicatedRects(humanRects).map {
                    geometricGroup(
                        rect: $0,
                        shape: .rectangle,
                        source: .detectedPerson
                    )
                },
                nil
            )
        }

        // Do not infer a full-body rectangle from a face alone. On portrait
        // media that estimate can cover nearly the entire frame. A tight face
        // fallback still protects identity and remains editable by the user.
        let faceFallbackRects = (faces.results ?? [])
            .filter { $0.confidence >= 0.35 }
            .map {
                NormalizedVideoRect(
                    visionBoundingBox: $0.boundingBox
                ).expandedForFaceCoverage()
            }
        let groups = deduplicatedRects(faceFallbackRects)
            .map {
                geometricGroup(
                    rect: $0,
                    shape: .ellipse,
                    source: .detectedPerson
                )
            }
        return (groups, nil)
    }

    private static func faceGroups(
        in image: CIImage,
        foreground: ForegroundInstances?
    ) -> [PhotoMaskGroup] {
        let request = VNDetectFaceRectanglesRequest()
        configureCPU(request)
        try? VNImageRequestHandler(ciImage: image, orientation: .up)
            .perform([request])
        let candidates = deduplicatedRects(
            (request.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map {
                    NormalizedVideoRect(visionBoundingBox: $0.boundingBox)
                        .expandedForFaceCoverage()
                }
        )
        return candidates.map { rect in
            let track = MaskTrack(
                shape: .ellipse,
                source: .detectedFace,
                keyframes: [MaskKeyframe(timeSeconds: 0, rect: rect)]
            )
            guard let foreground,
                  let label = bestInstanceLabel(
                    in: foreground.plane,
                    overlapping: rect
                  ) else {
                return PhotoMaskGroup(track: track)
            }
            // The foreground instance contributes head/hair edges, while the
            // expanded face rect clips away the body and protects forehead,
            // ears, and chin.
            return PhotoMaskGroup(
                track: track,
                maskPlaneID: foreground.plane.id,
                instanceLabel: label,
                originalRect: rect
            )
        }
    }

    private static func petGroups(
        in image: CIImage,
        foreground: ForegroundInstances?
    ) -> [PhotoMaskGroup] {
        let request = VNRecognizeAnimalsRequest()
        configureCPU(request)
        try? VNImageRequestHandler(ciImage: image, orientation: .up)
            .perform([request])
        let candidates = deduplicatedRects(
            (request.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map {
                    padded(
                        NormalizedVideoRect(visionBoundingBox: $0.boundingBox),
                        horizontal: 0.06,
                        vertical: 0.06
                    )
                }
        )
        return candidates.map { rect in
            let track = MaskTrack(
                shape: .rectangle,
                source: .detectedPet,
                keyframes: [MaskKeyframe(timeSeconds: 0, rect: rect)]
            )
            guard let foreground,
                  let label = bestInstanceLabel(
                    in: foreground.plane,
                    overlapping: rect
                  ) else {
                return PhotoMaskGroup(track: track)
            }
            // Cropping the foreground instance to this animal region prevents
            // a person and nearby pet that Vision grouped together from becoming
            // one inseparable mask.
            return PhotoMaskGroup(
                track: track,
                maskPlaneID: foreground.plane.id,
                instanceLabel: label,
                originalRect: rect
            )
        }
    }

    private struct ForegroundInstances {
        let plane: PhotoMaskPlane
    }

    private static func foregroundInstances(
        in image: CIImage
    ) -> ForegroundInstances? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let plane = makeMaskPlane(from: observation.instanceMask) else {
            return nil
        }
        return ForegroundInstances(plane: plane)
    }

    private static func semanticPersonMask(
        in image: CIImage
    ) -> CVPixelBuffer? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first?.pixelBuffer
    }

    private static func intersect(
        _ plane: PhotoMaskPlane,
        withPersonMask personMask: CVPixelBuffer
    ) -> PhotoMaskPlane? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(personMask)
        guard pixelFormat == kCVPixelFormatType_OneComponent8
                || pixelFormat == kCVPixelFormatType_OneComponent32Float,
              plane.width > 0,
              plane.height > 0 else {
            return nil
        }
        let maskWidth = CVPixelBufferGetWidth(personMask)
        let maskHeight = CVPixelBufferGetHeight(personMask)
        guard maskWidth > 0, maskHeight > 0 else { return nil }

        let labelCount = plane.width * plane.height
        var labels = [UInt16](repeating: 0, count: labelCount)
        plane.labels.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let values = rawBuffer.bindMemory(to: UInt16.self)
            guard values.count >= labelCount else { return }
            labels.withUnsafeMutableBufferPointer { destination in
                for index in 0..<labelCount {
                    destination[index] = values[index]
                }
            }
        }

        CVPixelBufferLockBaseAddress(personMask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(personMask, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(personMask) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(personMask)
        for y in 0..<plane.height {
            let maskY = min(
                maskHeight - 1,
                Int((Double(y) + 0.5) * Double(maskHeight) / Double(plane.height))
            )
            let row = baseAddress.advanced(by: maskY * bytesPerRow)
            for x in 0..<plane.width where labels[y * plane.width + x] > 0 {
                let maskX = min(
                    maskWidth - 1,
                    Int((Double(x) + 0.5) * Double(maskWidth) / Double(plane.width))
                )
                let confidence: Float
                if pixelFormat == kCVPixelFormatType_OneComponent8 {
                    confidence = Float(
                        row.assumingMemoryBound(to: UInt8.self)[maskX]
                    ) / 255
                } else {
                    confidence = row
                        .assumingMemoryBound(to: Float.self)[maskX]
                }
                if confidence < 0.5 {
                    labels[y * plane.width + x] = 0
                }
            }
        }
        guard labels.contains(where: { $0 > 0 }) else { return nil }
        return labels.withUnsafeBytes {
            PhotoMaskPlane(
                width: plane.width,
                height: plane.height,
                labels: Data($0)
            )
        }
    }

    private static func makeMaskPlane(
        from pixelBuffer: CVPixelBuffer
    ) -> PhotoMaskPlane? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_OneComponent8
                || pixelFormat == kCVPixelFormatType_OneComponent32Float else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        var labels = [UInt16](repeating: 0, count: width * height)
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let rawValue: Int
                if pixelFormat == kCVPixelFormatType_OneComponent8 {
                    rawValue = Int(row.assumingMemoryBound(to: UInt8.self)[x])
                } else {
                    rawValue = Int(
                        row.assumingMemoryBound(to: Float.self)[x].rounded()
                    )
                }
                labels[y * width + x] = UInt16(
                    min(max(rawValue, 0), Int(UInt16.max))
                )
            }
        }
        return labels.withUnsafeBytes {
            PhotoMaskPlane(
                width: width,
                height: height,
                labels: Data($0)
            )
        }
    }

    private static func bestInstanceLabel(
        in plane: PhotoMaskPlane,
        overlapping rect: NormalizedVideoRect
    ) -> UInt16? {
        guard plane.width > 0, plane.height > 0 else { return nil }
        let region = rect.cgRect
        var totalCounts: [UInt16: Int] = [:]
        var overlapCounts: [UInt16: Int] = [:]
        plane.labels.withUnsafeBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: UInt16.self)
            guard values.count >= plane.width * plane.height else { return }
            for y in 0..<plane.height {
                let normalizedY = (Double(y) + 0.5) / Double(plane.height)
                for x in 0..<plane.width {
                    let label = values[y * plane.width + x]
                    guard label > 0 else { continue }
                    totalCounts[label, default: 0] += 1
                    let point = CGPoint(
                        x: (Double(x) + 0.5) / Double(plane.width),
                        y: normalizedY
                    )
                    if region.contains(point) {
                        overlapCounts[label, default: 0] += 1
                    }
                }
            }
        }

        let regionPixels = max(
            1,
            Int(region.width * Double(plane.width)
                * region.height * Double(plane.height))
        )
        return overlapCounts.max { lhs, rhs in
            score(
                intersection: lhs.value,
                total: totalCounts[lhs.key] ?? 0,
                regionPixels: regionPixels
            ) < score(
                intersection: rhs.value,
                total: totalCounts[rhs.key] ?? 0,
                regionPixels: regionPixels
            )
        }.flatMap { label, intersection in
            let matchScore = score(
                intersection: intersection,
                total: totalCounts[label] ?? 0,
                regionPixels: regionPixels
            )
            return intersection >= 4 && matchScore >= 0.01 ? label : nil
        }
    }

    private static func score(
        intersection: Int,
        total: Int,
        regionPixels: Int
    ) -> Double {
        let union = max(1, total + regionPixels - intersection)
        return Double(intersection) / Double(union)
    }

    private static func combinedEdgeMask(
        groups: [PhotoMaskGroup],
        planes: [PhotoMaskPlane],
        extent: CGRect
    ) -> CIImage? {
        let planesByID = Dictionary(uniqueKeysWithValues: planes.map { ($0.id, $0) })
        var combined: CIImage?
        for group in groups {
            guard let planeID = group.maskPlaneID,
                  let label = group.instanceLabel,
                  let plane = planesByID[planeID],
                  let mask = edgeMask(
                    group: group,
                    plane: plane,
                    label: label,
                    extent: extent
                  ) else {
                continue
            }
            if let existing = combined {
                combined = mask.applyingFilter(
                    "CIMaximumCompositing",
                    parameters: [kCIInputBackgroundImageKey: existing]
                ).cropped(to: extent)
            } else {
                combined = mask.cropped(to: extent)
            }
        }
        return combined
    }

    private static func edgeMask(
        group: PhotoMaskGroup,
        plane: PhotoMaskPlane,
        label: UInt16,
        extent: CGRect
    ) -> CIImage? {
        guard let currentRect = group.track.rect(at: 0),
              !currentRect.isEmpty,
              !group.originalRect.isEmpty,
              let rawMask = binaryMaskImage(from: plane, label: label) else {
            return nil
        }
        let scaled = rawMask.transformed(
            by: CGAffineTransform(
                scaleX: extent.width / rawMask.extent.width,
                y: extent.height / rawMask.extent.height
            )
        )
        let original = group.originalRect.rect(inCoreImageExtent: extent)
        let current = currentRect.rect(inCoreImageExtent: extent)
        guard original.width > 0, original.height > 0 else { return nil }
        let scaleX = current.width / original.width
        let scaleY = current.height / original.height
        let transform = CGAffineTransform(
            a: scaleX,
            b: 0,
            c: 0,
            d: scaleY,
            tx: current.minX - original.minX * scaleX,
            ty: current.minY - original.minY * scaleY
        )
        let transformed = scaled
            .cropped(to: original)
            .transformed(by: transform)
            .cropped(to: extent)
        let black = CIImage(color: .black).cropped(to: extent)
        return transformed.composited(over: black).cropped(to: extent)
    }

    private static func binaryMaskImage(
        from plane: PhotoMaskPlane,
        label: UInt16
    ) -> CIImage? {
        guard plane.width > 0, plane.height > 0 else { return nil }
        var alpha = [UInt8](repeating: 0, count: plane.width * plane.height)
        plane.labels.withUnsafeBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: UInt16.self)
            guard values.count >= alpha.count else { return }
            for index in alpha.indices where values[index] == label {
                alpha[index] = 255
            }
        }
        let data = Data(alpha)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: plane.width,
                height: plane.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: plane.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.none.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }

    private static func geometricGroup(
        rect: NormalizedVideoRect,
        shape: MaskTrackShape,
        source: MaskTrackSource
    ) -> PhotoMaskGroup {
        PhotoMaskGroup(
            track: MaskTrack(
                shape: shape,
                source: source,
                keyframes: [MaskKeyframe(timeSeconds: 0, rect: rect)]
            )
        )
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

    private static func deduplicatedRects(
        _ rects: [NormalizedVideoRect]
    ) -> [NormalizedVideoRect] {
        var accepted: [NormalizedVideoRect] = []
        for rect in rects.sorted(by: {
            $0.width * $0.height > $1.width * $1.height
        }) {
            if !accepted.contains(where: {
                intersectionOverUnion($0.cgRect, rect.cgRect) >= 0.65
            }) {
                accepted.append(rect)
            }
        }
        return accepted
    }

    private static func intersectionOverUnion(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return 0
        }
        let area = intersection.width * intersection.height
        let union = lhs.width * lhs.height + rhs.width * rhs.height - area
        return union > 0 ? Double(area / union) : 0
    }
}
