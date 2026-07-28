@preconcurrency import AVFoundation
import CoreImage
import Photos
import UIKit
import Vision

@MainActor
final class VideoProcessor: ObservableObject {
    @Published private(set) var stage: ProcessingStage = .idle
    @Published private(set) var progress = 0.0 {
        didSet { updateEstimatedRemainingTime() }
    }
    @Published private(set) var outputURL: URL?
    @Published private(set) var advisory: String?
    @Published private(set) var estimatedRemainingSeconds: TimeInterval?
    private var exportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?
    private var processingStartedAt: Date?
    private static let chunkDurationSeconds = 60.0

    var isRunning: Bool {
        switch stage {
        case .reading, .loadingModel, .warmingUp, .analyzing, .encoding: true
        default: false
        }
    }

    func process(sourceURL: URL, options: ProcessingOptions, bundle: Bundle = .main) async {
        cancel()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
        advisory = nil
        estimatedRemainingSeconds = nil
        processingStartedAt = Date()
        progress = 0
        stage = .reading
        var pendingDestination: URL?
        // Keep screen awake for the whole export; lock/sleep commonly yields
        // AVErrorOperationInterrupted ("The operation was interrupted").
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            if let pendingDestination {
                try? FileManager.default.removeItem(at: pendingDestination)
            }
        }

        do {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite, duration.seconds > 0 else {
                throw ProcessorError.invalidVideo
            }
            let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let capacity = try FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            // During chunked export both the processed chunks and their joined
            // result briefly coexist. Reserve enough room for both plus margin.
            let durationBasedCapacity = Int64(duration.seconds * 5_000_000)
            let requiredCapacity = max(
                Int64(fileSize) * 5,
                durationBasedCapacity,
                250_000_000
            )
            guard capacity == 0 || capacity > requiredCapacity else {
                throw ProcessorError.insufficientStorage
            }

            var effectiveOptions = options
            if options.quality == .precise && Self.shouldDowngradePreciseMode {
                effectiveOptions.quality = .balanced
                advisory = String(localized: "advisory.resource", bundle: bundle)
            }

            stage = .loadingModel
            try Task.checkCancellation()
            let processor = FrameEffectProcessor(options: effectiveOptions)

            stage = .warmingUp
            await processor.warmUp()
            try Task.checkCancellation()

            stage = .analyzing
            progress = 0.08
            let composition = AVVideoComposition(asset: asset) { request in
                request.finish(with: processor.render(request.sourceImage), context: nil)
            }

            stage = .encoding
            // ASCII-only: Photos rejects / crashes on some non-ASCII temp paths.
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("jingyin-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: destination)
            pendingDestination = destination

            switch effectiveOptions.audio {
            case .voice:
                try await exportWithVoicePitch(
                    asset: asset,
                    composition: composition,
                    duration: duration,
                    sourceURL: sourceURL,
                    semitones: effectiveOptions.voicePitch,
                    destination: destination,
                    bundle: bundle
                )
            case .original, .mute:
                try await exportProcessedVideo(
                    asset: asset,
                    composition: composition,
                    duration: duration,
                    muted: effectiveOptions.audio == .mute,
                    destination: destination,
                    progressStart: 0.1,
                    progressSpan: 0.88
                )
            }

            outputURL = destination
            pendingDestination = nil
            progress = 1
            estimatedRemainingSeconds = nil
            processingStartedAt = nil
            stage = .completed(destination)
        } catch is CancellationError {
            estimatedRemainingSeconds = nil
            processingStartedAt = nil
            stage = .failed(String(localized: "error.cancelled", bundle: bundle))
        } catch {
            estimatedRemainingSeconds = nil
            processingStartedAt = nil
            stage = .failed(Self.message(for: error, bundle: bundle))
        }
    }

    func cancel() {
        progressTask?.cancel()
        progressTask = nil
        exportSession?.cancelExport()
        exportSession = nil
    }

    func saveToPhotos() async -> Bool {
        guard let outputURL else { return false }
        guard FileManager.default.fileExists(atPath: outputURL.path) else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        let fileURL = outputURL
        do {
            try await Self.addVideoToPhotos(fileURL)
            return true
        } catch {
            return false
        }
    }

    /// `PHPhotoLibrary` executes its changes block on a private queue. Keeping
    /// this helper nonisolated prevents Swift 6 from inheriting MainActor onto
    /// that block and trapping when Photos invokes it off the main queue.
    nonisolated private static func addVideoToPhotos(_ fileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }

    private func exportWithVoicePitch(
        asset: AVAsset,
        composition: AVVideoComposition,
        duration: CMTime,
        sourceURL: URL,
        semitones: Int,
        destination: URL,
        bundle: Bundle
    ) async throws {
        let mutedVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-muted-\(UUID().uuidString).mp4")
        var pitchedAudioURL: URL?
        defer {
            try? FileManager.default.removeItem(at: mutedVideoURL)
            if let pitchedAudioURL {
                try? FileManager.default.removeItem(at: pitchedAudioURL)
            }
        }

        try await exportProcessedVideo(
            asset: asset,
            composition: composition,
            duration: duration,
            muted: true,
            destination: mutedVideoURL,
            progressStart: 0.1,
            progressSpan: 0.55
        )

        try Task.checkCancellation()
        progress = 0.68

        do {
            let audioURL = try await VoicePitchExporter.renderPitchedAudio(
                from: sourceURL,
                semitones: semitones
            ) { [weak self] value in
                Task { @MainActor in
                    self?.progress = 0.68 + value * 0.18
                }
            }
            pitchedAudioURL = audioURL
            progress = 0.88
            try await VoicePitchExporter.mux(
                videoURL: mutedVideoURL,
                audioURL: audioURL,
                outputURL: destination
            )
        } catch VoicePitchExporter.ExportError.noAudioTrack {
            advisory = String(localized: "advisory.noAudio", bundle: bundle)
            try FileManager.default.copyItem(at: mutedVideoURL, to: destination)
        } catch let error as VoicePitchExporter.ExportError {
            throw error
        } catch {
            throw VoicePitchExporter.ExportError.renderFailed
        }
    }

    private func exportProcessedVideo(
        asset: AVAsset,
        composition: AVVideoComposition,
        duration: CMTime,
        muted: Bool,
        destination: URL,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        let ranges = Self.chunkRanges(for: duration)
        guard ranges.count > 1 else {
            try await exportSegment(
                asset: asset,
                composition: composition,
                timeRange: nil,
                muted: muted,
                destination: destination,
                progressStart: progressStart,
                progressSpan: progressSpan
            )
            return
        }

        let chunkURLs = ranges.indices.map { index in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("jingyin-chunk-\(UUID().uuidString)-\(index).mp4")
        }
        defer {
            for url in chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Leave the final 8% of this phase for joining the already encoded
        // chunks. The join uses passthrough and therefore does not re-render.
        let encodingSpan = progressSpan * 0.92
        let chunkSpan = encodingSpan / Double(ranges.count)
        for index in ranges.indices {
            try Task.checkCancellation()
            try await exportSegment(
                asset: asset,
                composition: composition,
                timeRange: ranges[index],
                muted: muted,
                destination: chunkURLs[index],
                progressStart: progressStart + Double(index) * chunkSpan,
                progressSpan: chunkSpan
            )
        }

        try Task.checkCancellation()
        try await joinChunks(
            chunkURLs,
            destination: destination,
            progressStart: progressStart + encodingSpan,
            progressSpan: progressSpan - encodingSpan
        )
    }

    private func exportSegment(
        asset: AVAsset,
        composition: AVVideoComposition,
        timeRange: CMTimeRange?,
        muted: Bool,
        destination: URL,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw ProcessorError.encoderUnavailable
        }
        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = .mp4
        session.videoComposition = composition
        if let timeRange {
            session.timeRange = timeRange
        }
        if muted {
            session.audioMix = try await Self.mutedAudioMix(for: asset)
        }
        try await run(
            session,
            progressStart: progressStart,
            progressSpan: progressSpan
        )
    }

    private func joinChunks(
        _ urls: [URL],
        destination: URL,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ProcessorError.exportFailed
        }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var insertionTime = CMTime.zero
        var appliedTransform = false

        for url in urls {
            try Task.checkCancellation()
            let chunk = AVURLAsset(url: url)
            let chunkDuration = try await chunk.load(.duration)
            let range = CMTimeRange(start: .zero, duration: chunkDuration)
            guard let sourceVideoTrack = try await chunk.loadTracks(withMediaType: .video).first else {
                throw ProcessorError.exportFailed
            }
            try videoTrack.insertTimeRange(range, of: sourceVideoTrack, at: insertionTime)
            if !appliedTransform {
                videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
                appliedTransform = true
            }
            if let sourceAudioTrack = try await chunk.loadTracks(withMediaType: .audio).first {
                let audioDuration = try await sourceAudioTrack.load(.timeRange).duration
                try audioTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: CMTimeMinimum(chunkDuration, audioDuration)),
                    of: sourceAudioTrack,
                    at: insertionTime
                )
            }
            insertionTime = CMTimeAdd(insertionTime, chunkDuration)
        }

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ProcessorError.encoderUnavailable
        }
        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = .mp4
        try await run(
            session,
            progressStart: progressStart,
            progressSpan: progressSpan
        )
    }

    private func run(
        _ session: AVAssetExportSession,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        exportSession = session
        progressTask?.cancel()
        progressTask = Task { [weak self, weak session] in
            while let session, !Task.isCancelled {
                self?.progress = progressStart + Double(session.progress) * progressSpan
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        await session.export()
        progressTask?.cancel()
        progressTask = nil
        exportSession = nil

        switch session.status {
        case .completed:
            progress = progressStart + progressSpan
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? ProcessorError.exportFailed
        }
    }

    private static func chunkRanges(for duration: CMTime) -> [CMTimeRange] {
        let totalSeconds = duration.seconds
        guard totalSeconds.isFinite, totalSeconds > chunkDurationSeconds else {
            return [CMTimeRange(start: .zero, duration: duration)]
        }
        var ranges: [CMTimeRange] = []
        var startSeconds = 0.0
        while startSeconds < totalSeconds {
            let segmentSeconds = min(chunkDurationSeconds, totalSeconds - startSeconds)
            ranges.append(CMTimeRange(
                start: CMTime(seconds: startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: segmentSeconds, preferredTimescale: 600)
            ))
            startSeconds += segmentSeconds
        }
        return ranges
    }

    private static func mutedAudioMix(for asset: AVAsset) async throws -> AVAudioMix {
        let mix = AVMutableAudioMix()
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        mix.inputParameters = tracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0, at: .zero)
            return parameters
        }
        return mix
    }

    private static func message(for error: Error, bundle: Bundle) -> String {
        if let processorError = error as? ProcessorError {
            return processorError.localizedMessage(bundle: bundle)
        }
        if let voiceError = error as? VoicePitchExporter.ExportError {
            return voiceError.localizedMessage(bundle: bundle)
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        let template = String(localized: "error.exportPrefix", bundle: bundle)
        return String(format: template, locale: Locale.current, error.localizedDescription)
    }

    private static var shouldDowngradePreciseMode: Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        return ProcessInfo.processInfo.physicalMemory < 4_000_000_000
            || thermal == .serious
            || thermal == .critical
    }

    private func updateEstimatedRemainingTime() {
        guard let processingStartedAt,
              progress >= 0.03,
              progress < 1 else {
            return
        }
        let elapsed = Date().timeIntervalSince(processingStartedAt)
        guard elapsed >= 2 else { return }
        let rawEstimate = elapsed / progress * (1 - progress)
        guard rawEstimate.isFinite, rawEstimate >= 0 else { return }
        if let current = estimatedRemainingSeconds {
            estimatedRemainingSeconds = current * 0.75 + rawEstimate * 0.25
        } else {
            estimatedRemainingSeconds = rawEstimate
        }
    }
}

private enum ProcessorError: Error {
    case invalidVideo
    case insufficientStorage
    case encoderUnavailable
    case exportFailed

    func localizedMessage(bundle: Bundle) -> String {
        switch self {
        case .invalidVideo:
            String(localized: "error.invalidVideo", bundle: bundle)
        case .insufficientStorage:
            String(localized: "error.insufficientStorage", bundle: bundle)
        case .encoderUnavailable:
            String(localized: "error.encoderUnavailable", bundle: bundle)
        case .exportFailed:
            String(localized: "error.exportFailed", bundle: bundle)
        }
    }
}

final class FrameEffectProcessor: @unchecked Sendable {
    private let options: ProcessingOptions
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private let asciiGlyphTiles: [CIImage]
    private var cachedMask: CIImage?
    private var frameIndex = 0

    init(options: ProcessingOptions) {
        self.options = options
        asciiGlyphTiles = options.style == .ascii
            ? Self.makeASCIIGlyphTiles(cellSize: CGFloat(options.strength))
            : []
    }

    func warmUp() async {
        _ = context.createCGImage(CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)), from: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    func render(_ source: CIImage) -> CIImage {
        let extent = source.extent
        let effected: CIImage
        switch options.style {
        case .blur:
            effected = source
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: options.strength])
                .cropped(to: extent)
        case .pixel:
            effected = source
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: max(8, options.strength),
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY)
                ])
                .cropped(to: extent)
        case .ascii:
            effected = asciiImage(for: source)
        }
        guard options.scope != .full else { return effected }

        lock.lock()
        defer { lock.unlock() }
        frameIndex += 1
        if frameIndex == 1 || frameIndex.isMultiple(of: options.quality.frameInterval) {
            cachedMask = subjectMask(for: source, extent: extent) ?? cachedMask
        }
        guard var mask = cachedMask else { return source }
        let safetyRadius: Double
        let featherRadius: Double
        switch options.quality {
        case .fast:
            safetyRadius = max(5, min(12, Double(min(extent.width, extent.height)) * 0.009))
            featherRadius = 4
        case .balanced:
            safetyRadius = max(3, min(8, Double(min(extent.width, extent.height)) * 0.005))
            featherRadius = 2.5
        case .precise:
            safetyRadius = max(1, min(3, Double(min(extent.width, extent.height)) * 0.0018))
            featherRadius = 1.25
        }
        mask = mask
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: safetyRadius])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius])
            .cropped(to: extent)
        if options.scope == .background {
            mask = mask.applyingFilter("CIColorInvert")
        }
        return effected.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: source,
            kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }

    private func subjectMask(for image: CIImage, extent: CGRect) -> CIImage? {
        var masks: [CIImage] = []
        if options.subjects.contains(.person), let mask = personMask(for: image, extent: extent) {
            masks.append(mask)
        }
        if options.subjects.contains(.face), let mask = faceMask(for: image, extent: extent) {
            masks.append(mask)
        }
        if options.subjects.contains(.pet), let mask = petMask(for: image, extent: extent) {
            masks.append(mask)
        }
        guard var combined = masks.first else { return nil }
        for mask in masks.dropFirst() {
            combined = mask.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: combined
            ])
        }
        return combined.cropped(to: extent)
    }

    private func personMask(for image: CIImage, extent: CGRect) -> CIImage? {
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = options.quality == .fast ? .fast : (options.quality == .precise ? .accurate : .balanced)
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            let segmentationHandler = VNImageRequestHandler(ciImage: image, orientation: .up)
            try segmentationHandler.perform([segmentation])
            if let buffer = segmentation.results?.first?.pixelBuffer {
                let semanticMask = scaledMask(from: buffer, to: extent)
                if options.quality == .precise,
                   let foregroundMask = foregroundInstanceMask(for: image, extent: extent) {
                    // The semantic request identifies people; the foreground request
                    // contributes the higher-resolution hair, clothing and limb edges.
                    let semanticSafety = semanticMask
                        .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 6])
                        .cropped(to: extent)
                    return foregroundMask
                        .applyingFilter("CIMinimumCompositing", parameters: [
                            kCIInputBackgroundImageKey: semanticSafety
                        ])
                        .cropped(to: extent)
                }
                return semanticMask
            }
        } catch {
            // Rectangle detection below is only a fallback. Mixing rectangles into
            // a successful pixel mask would destroy the person's precise outline.
        }

        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let faces = VNDetectFaceRectanglesRequest()
        do {
            let detectionHandler = VNImageRequestHandler(ciImage: image, orientation: .up)
            try detectionHandler.perform([humans, faces])
            let humanBoxes: [CGRect] = (humans.results ?? []).map { $0.boundingBox }
            let faceBoxes: [CGRect] = (faces.results ?? []).map { face in
                let box = face.boundingBox
                return box.insetBy(dx: -box.width * 1.2, dy: -box.height * 1.8)
            }
            let detected = humanBoxes + faceBoxes
            return boxMask(for: detected, extent: extent, padding: 0.035)
        } catch {
            return nil
        }
    }

    private func foregroundInstanceMask(
        for image: CIImage,
        extent: CGRect,
        matching normalizedBoxes: [CGRect]? = nil
    ) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                return nil
            }
            let instances: IndexSet
            if let normalizedBoxes {
                let matchedInstances = matchingForegroundInstances(
                    in: observation.instanceMask,
                    candidates: observation.allInstances,
                    overlapping: normalizedBoxes
                )
                // A foreground-mask implementation may use an unexpected label
                // format on a new OS/device. Using every foreground instance and
                // clipping it to the detected pet box still preserves a pixel
                // outline, while the rectangle below remains the final fallback.
                instances = matchedInstances.isEmpty
                    ? observation.allInstances
                    : matchedInstances
            } else {
                instances = observation.allInstances
            }
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: instances,
                from: handler
            )
            let instanceMask = scaledMask(from: buffer, to: extent)
            guard let normalizedBoxes,
                  let animalRegion = boxMask(
                    for: normalizedBoxes,
                    extent: extent,
                    padding: 0.025
                  ) else {
                return instanceMask
            }
            // Foreground lifting can occasionally group a nearby person and pet
            // as one instance. Restrict the selected instance to the animal
            // detector's padded region so choosing “pet” cannot mask the owner.
            return instanceMask
                .applyingFilter("CIMinimumCompositing", parameters: [
                    kCIInputBackgroundImageKey: animalRegion
                ])
                .cropped(to: extent)
        } catch {
            return nil
        }
    }

    private func matchingForegroundInstances(
        in instanceMask: CVPixelBuffer,
        candidates: IndexSet,
        overlapping boxes: [CGRect]
    ) -> IndexSet {
        let pixelFormat = CVPixelBufferGetPixelFormatType(instanceMask)
        guard pixelFormat == kCVPixelFormatType_OneComponent8
                || pixelFormat == kCVPixelFormatType_OneComponent32Float,
              !boxes.isEmpty else {
            return []
        }

        let width = CVPixelBufferGetWidth(instanceMask)
        let height = CVPixelBufferGetHeight(instanceMask)
        guard width > 0, height > 0 else { return [] }

        let regions = boxes.map { box in
            box.insetBy(
                dx: -max(0.012, box.width * 0.08),
                dy: -max(0.012, box.height * 0.08)
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var totalCounts: [Int: Int] = [:]
        var overlapCounts = Array(repeating: [Int: Int](), count: regions.count)

        CVPixelBufferLockBaseAddress(instanceMask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(instanceMask, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(instanceMask) else { return [] }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(instanceMask)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow)
            // Vision bounding boxes use a bottom-left origin, while pixel-buffer
            // rows are top-to-bottom.
            let normalizedY = 1 - (CGFloat(y) + 0.5) / CGFloat(height)
            for x in 0..<width {
                let instance: Int
                if pixelFormat == kCVPixelFormatType_OneComponent8 {
                    instance = Int(row.assumingMemoryBound(to: UInt8.self)[x])
                } else {
                    instance = Int(
                        row.assumingMemoryBound(to: Float.self)[x].rounded()
                    )
                }
                guard instance > 0, candidates.contains(instance) else { continue }
                totalCounts[instance, default: 0] += 1
                let point = CGPoint(
                    x: (CGFloat(x) + 0.5) / CGFloat(width),
                    y: normalizedY
                )
                for index in regions.indices where regions[index].contains(point) {
                    overlapCounts[index][instance, default: 0] += 1
                }
            }
        }

        var selected = IndexSet()
        for (regionIndex, region) in regions.enumerated() {
            let regionPixels = max(
                1,
                Int(region.width * CGFloat(width) * region.height * CGFloat(height))
            )
            var bestInstance: Int?
            var bestIntersectionOverUnion = 0.0
            for (instance, intersection) in overlapCounts[regionIndex] {
                guard intersection >= 4, let total = totalCounts[instance] else { continue }
                let union = max(1, total + regionPixels - intersection)
                let intersectionOverUnion = Double(intersection) / Double(union)
                if intersectionOverUnion > bestIntersectionOverUnion {
                    bestIntersectionOverUnion = intersectionOverUnion
                    bestInstance = instance
                }
            }
            if bestIntersectionOverUnion >= 0.01, let bestInstance {
                selected.insert(bestInstance)
            }
        }
        return selected
    }

    private func faceMask(for image: CIImage, extent: CGRect) -> CIImage? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        do {
            try handler.perform([request])
            let boxes = (request.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map(\.boundingBox)
            return ellipseMask(for: boxes, extent: extent)
        } catch {
            return nil
        }
    }

    private func petMask(for image: CIImage, extent: CGRect) -> CIImage? {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        do {
            try handler.perform([request])
            guard let observations = request.results, !observations.isEmpty else { return nil }
            let boxes = observations
                .filter { $0.confidence >= 0.35 }
                .map(\.boundingBox)
            guard !boxes.isEmpty else { return nil }
            if let preciseMask = foregroundInstanceMask(
                for: image,
                extent: extent,
                matching: boxes
            ) {
                return preciseMask
            }
            // Older/unsupported devices and frames without a foreground
            // instance keep the previous privacy-safe rectangle fallback.
            return boxMask(for: boxes, extent: extent, padding: 0.025)
        } catch {
            return nil
        }
    }

    private func boxMask(for boxes: [CGRect], extent: CGRect, padding: CGFloat) -> CIImage? {
        guard !boxes.isEmpty else { return nil }
        var mask = CIImage(color: .black).cropped(to: extent)
        for box in boxes {
            let clamped = box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            let rect = CGRect(
                x: extent.minX + clamped.minX * extent.width,
                y: extent.minY + clamped.minY * extent.height,
                width: clamped.width * extent.width,
                height: clamped.height * extent.height
            ).insetBy(dx: -extent.width * padding, dy: -extent.height * padding)
            mask = CIImage(color: .white).cropped(to: rect).composited(over: mask)
        }
        return mask.cropped(to: extent)
    }

    private func ellipseMask(for boxes: [CGRect], extent: CGRect) -> CIImage? {
        guard !boxes.isEmpty else { return nil }
        var mask = CIImage(color: .black).cropped(to: extent)
        for box in boxes {
            let clamped = box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { continue }
            var rect = CGRect(
                x: extent.minX + clamped.minX * extent.width,
                y: extent.minY + clamped.minY * extent.height,
                width: clamped.width * extent.width,
                height: clamped.height * extent.height
            )
            // Face observations are tight around facial features. Include forehead,
            // chin and ears so the identity-bearing region cannot leak at the edge.
            rect = rect.insetBy(dx: -rect.width * 0.24, dy: -rect.height * 0.30)
            let ellipse = CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: 0.5, y: 0.5),
                    "inputRadius0": 0.43,
                    "inputRadius1": 0.5,
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.black
                ]
            )!.outputImage!
                .transformed(by: CGAffineTransform(scaleX: rect.width, y: rect.height))
                .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
                .cropped(to: extent)
            mask = ellipse.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: mask
            ])
        }
        return mask.cropped(to: extent)
    }

    private func scaledMask(from buffer: CVPixelBuffer, to extent: CGRect) -> CIImage {
        let raw = CIImage(cvPixelBuffer: buffer)
        return raw
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / raw.extent.width,
                y: extent.height / raw.extent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX,
                y: extent.minY
            ))
            .cropped(to: extent)
    }

    private func asciiImage(for source: CIImage) -> CIImage {
        let extent = source.extent
        guard !asciiGlyphTiles.isEmpty else {
            return source
                .applyingFilter("CIPhotoEffectNoir")
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: max(8, options.strength)
                ])
                .cropped(to: extent)
        }

        let cellSize = CGFloat(max(8, options.strength))
        let sampled = source
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            ])
            .applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: cellSize,
                kCIInputCenterKey: CIVector(
                    x: extent.minX + cellSize / 2,
                    y: extent.minY + cellSize / 2
                )
            ])
            .cropped(to: extent)

        let white = CIImage(color: .white).cropped(to: extent)
        let clear = CIImage(color: .clear).cropped(to: extent)
        var result = CIImage(color: CIColor(red: 0.02, green: 0.027, blue: 0.024))
            .cropped(to: extent)
        let count = asciiGlyphTiles.count

        for (index, tile) in asciiGlyphTiles.enumerated() where index > 0 {
            let low = Double(index) / Double(count)
            let high = Double(index + 1) / Double(count)
            let aboveLow = sampled.applyingFilter("CIColorThreshold", parameters: [
                "inputThreshold": low
            ])
            let belowHigh = index == count - 1
                ? white
                : sampled
                    .applyingFilter("CIColorThreshold", parameters: [
                        "inputThreshold": high
                    ])
                    .applyingFilter("CIColorInvert")
            let band = aboveLow
                .applyingFilter("CIMultiplyCompositing", parameters: [
                    kCIInputBackgroundImageKey: belowHigh
                ])
                .cropped(to: extent)
            let tiledGlyph = tile
                .applyingFilter("CIAffineTile")
                .cropped(to: extent)
            let maskedGlyph = tiledGlyph
                .applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: clear,
                    kCIInputMaskImageKey: band
                ])
                .cropped(to: extent)
            result = maskedGlyph.composited(over: result)
        }
        return result.cropped(to: extent)
    }

    private static func makeASCIIGlyphTiles(cellSize: CGFloat) -> [CIImage] {
        // Same light-to-dark ramp used by the web editor.
        let glyphs = Array(" .,:;irsXA253hMHGS#9B&@").map(String.init)
        let side = max(8, ceil(cellSize))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let font = UIFont.monospacedSystemFont(ofSize: side * 0.82, weight: .bold)

        return glyphs.compactMap { glyph in
            let image = UIGraphicsImageRenderer(
                size: CGSize(width: side, height: side),
                format: format
            ).image { _ in
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(
                        red: 0.957,
                        green: 0.969,
                        blue: 0.961,
                        alpha: 1
                    )
                ]
                let size = (glyph as NSString).size(withAttributes: attributes)
                (glyph as NSString).draw(
                    at: CGPoint(
                        x: (side - size.width) / 2,
                        y: (side - size.height) / 2
                    ),
                    withAttributes: attributes
                )
            }
            return CIImage(image: image)
        }
    }
}
