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
    private var estimateStartedAt: Date?
    private var estimateLastUpdatedAt: Date?
    private var estimateAnchorProgress = 0.0
    private var estimateTargetProgress = 1.0
    private var estimateTailSeconds = 0.0
    private static let chunkDurationSeconds = 60.0

    var isRunning: Bool {
        switch stage {
        case .reading, .loadingModel, .warmingUp, .analyzing, .encoding: true
        default: false
        }
    }

    func process(
        sourceURL: URL,
        options: ProcessingOptions,
        access: ExportAccess,
        bundle: Bundle = .main
    ) async {
        cancel()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
        advisory = nil
        clearRemainingTimeEstimate()
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
            guard duration.seconds <= ProductLimits.maximumInputDurationSeconds else {
                throw ProcessorError.videoTooLong
            }
            let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= ProductLimits.maximumInputFileSizeBytes else {
                throw ProcessorError.fileTooLarge
            }
            let outputDuration = Self.outputDuration(
                sourceDuration: duration,
                access: access
            )
            let sourceTimeRange: CMTimeRange? = outputDuration < duration
                ? CMTimeRange(start: .zero, duration: outputDuration)
                : nil
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

            var effectiveOptions = access.enforce(on: options)
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
            let composition = AVMutableVideoComposition(asset: asset) { request in
                request.finish(
                    with: processor.render(
                        request.sourceImage,
                        at: request.compositionTime,
                        renderSize: request.renderSize
                    ),
                    context: nil
                )
            }
            Self.configure(
                composition,
                resolution: effectiveOptions.exportResolution,
                frameRate: effectiveOptions.exportFrameRate
            )

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
                    duration: outputDuration,
                    sourceTimeRange: sourceTimeRange,
                    sourceURL: sourceURL,
                    semitones: effectiveOptions.voicePitch,
                    destination: destination,
                    exportPreset: effectiveOptions.exportResolution.exportPreset,
                    bundle: bundle
                )
            case .original, .mute:
                beginRemainingTimeEstimate(from: 0.1, through: 0.98)
                try await exportProcessedVideo(
                    asset: asset,
                    composition: composition,
                    duration: outputDuration,
                    sourceTimeRange: sourceTimeRange,
                    muted: effectiveOptions.audio == .mute,
                    destination: destination,
                    exportPreset: effectiveOptions.exportResolution.exportPreset,
                    progressStart: 0.1,
                    progressSpan: 0.88
                )
            }

            // The view may disappear just after AVFoundation finishes. Honor
            // that cancellation before publishing a result that no screen
            // remains to clean up.
            try Task.checkCancellation()
            outputURL = destination
            pendingDestination = nil
            progress = 1
            clearRemainingTimeEstimate()
            stage = .completed(destination)
        } catch is CancellationError {
            clearRemainingTimeEstimate()
            stage = .failed(String(localized: "error.cancelled", bundle: bundle))
        } catch {
            clearRemainingTimeEstimate()
            stage = .failed(Self.message(for: error, bundle: bundle))
        }
    }

    func cancel() {
        progressTask?.cancel()
        progressTask = nil
        exportSession?.cancelExport()
        exportSession = nil
    }

    func discardOutput() {
        cancel()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
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
        sourceTimeRange: CMTimeRange?,
        sourceURL: URL,
        semitones: Int,
        destination: URL,
        exportPreset: String,
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

        beginRemainingTimeEstimate(
            from: 0.1,
            through: 0.65,
            tailSeconds: max(3, duration.seconds * 0.12)
        )
        try await exportProcessedVideo(
            asset: asset,
            composition: composition,
            duration: duration,
            sourceTimeRange: sourceTimeRange,
            muted: true,
            destination: mutedVideoURL,
            exportPreset: exportPreset,
            progressStart: 0.1,
            progressSpan: 0.55
        )

        try Task.checkCancellation()
        progress = 0.68
        beginRemainingTimeEstimate(
            from: 0.68,
            through: 0.86,
            tailSeconds: 2
        )

        do {
            let audioURL = try await VoicePitchExporter.renderPitchedAudio(
                from: sourceURL,
                semitones: semitones,
                maximumDuration: sourceTimeRange == nil ? nil : duration.seconds
            ) { [weak self] value in
                Task { @MainActor in
                    self?.progress = 0.68 + value * 0.18
                }
            }
            pitchedAudioURL = audioURL
            progress = 0.88
            estimatedRemainingSeconds = 2
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
        sourceTimeRange: CMTimeRange?,
        muted: Bool,
        destination: URL,
        exportPreset: String,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        let ranges = Self.chunkRanges(
            for: sourceTimeRange
                ?? CMTimeRange(start: .zero, duration: duration)
        )
        guard ranges.count > 1 else {
            try await exportSegment(
                asset: asset,
                composition: composition,
                timeRange: sourceTimeRange,
                muted: muted,
                destination: destination,
                exportPreset: exportPreset,
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
                exportPreset: exportPreset,
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
        exportPreset: String,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: exportPreset
        ) else {
            throw ProcessorError.encoderUnavailable
        }
        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = .mp4
        session.metadata = []
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
        session.metadata = []
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

    private static func chunkRanges(for timeRange: CMTimeRange) -> [CMTimeRange] {
        let totalSeconds = timeRange.duration.seconds
        guard totalSeconds.isFinite, totalSeconds > chunkDurationSeconds else {
            return [timeRange]
        }
        var ranges: [CMTimeRange] = []
        let rangeStartSeconds = timeRange.start.seconds
        var elapsedSeconds = 0.0
        while elapsedSeconds < totalSeconds {
            let segmentSeconds = min(chunkDurationSeconds, totalSeconds - elapsedSeconds)
            ranges.append(CMTimeRange(
                start: CMTime(
                    seconds: rangeStartSeconds + elapsedSeconds,
                    preferredTimescale: 600
                ),
                duration: CMTime(seconds: segmentSeconds, preferredTimescale: 600)
            ))
            elapsedSeconds += segmentSeconds
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
        guard let estimateStartedAt,
              progress > estimateAnchorProgress,
              progress < estimateTargetProgress else {
            return
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(estimateStartedAt)
        let completedFraction = (progress - estimateAnchorProgress)
            / (estimateTargetProgress - estimateAnchorProgress)
        // The first few percent of AVAssetExportSession progress are dominated
        // by setup and produce the misleading, ever-growing estimate we want
        // to avoid showing.
        guard elapsed >= 3, completedFraction >= 0.04 else { return }
        if let lastUpdate = estimateLastUpdatedAt,
           now.timeIntervalSince(lastUpdate) < 0.75 {
            return
        }
        let rawEstimate = elapsed / completedFraction * (1 - completedFraction)
            + estimateTailSeconds
        guard rawEstimate.isFinite, rawEstimate >= 0 else { return }
        if let current = estimatedRemainingSeconds,
           let lastUpdate = estimateLastUpdatedAt {
            let updateInterval = now.timeIntervalSince(lastUpdate)
            let countdownValue = max(0, current - updateInterval)
            let smoothed = countdownValue * 0.8 + rawEstimate * 0.2
            // Real processing can slow down under thermal pressure, so allow a
            // small correction without letting the visible ETA jump upward.
            estimatedRemainingSeconds = min(
                smoothed,
                countdownValue + max(0.5, updateInterval * 0.25)
            )
        } else {
            estimatedRemainingSeconds = rawEstimate
        }
        estimateLastUpdatedAt = now
    }

    private func beginRemainingTimeEstimate(
        from anchorProgress: Double,
        through targetProgress: Double,
        tailSeconds: TimeInterval = 0
    ) {
        estimateAnchorProgress = anchorProgress
        estimateTargetProgress = targetProgress
        estimateTailSeconds = tailSeconds
        estimateStartedAt = Date()
        estimateLastUpdatedAt = nil
        estimatedRemainingSeconds = nil
    }

    private func clearRemainingTimeEstimate() {
        estimateStartedAt = nil
        estimateLastUpdatedAt = nil
        estimateTailSeconds = 0
        estimatedRemainingSeconds = nil
    }

    private static func configure(
        _ composition: AVMutableVideoComposition,
        resolution: ExportResolution,
        frameRate: Int
    ) {
        let sourceSize = composition.renderSize
        let sourceShortEdge = min(sourceSize.width, sourceSize.height)
        let targetShortEdge = min(sourceShortEdge, CGFloat(resolution.rawValue))
        if sourceShortEdge > 0, targetShortEdge < sourceShortEdge {
            let scale = targetShortEdge / sourceShortEdge
            composition.renderSize = CGSize(
                width: evenPixelSize(sourceSize.width * scale),
                height: evenPixelSize(sourceSize.height * scale)
            )
        }
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, frameRate))
        )
    }

    private static func evenPixelSize(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded(.down) * 2)
    }

    private static func outputDuration(
        sourceDuration: CMTime,
        access: ExportAccess
    ) -> CMTime {
        guard let maximumDurationSeconds = access.maximumDurationSeconds,
              sourceDuration.seconds > maximumDurationSeconds else {
            return sourceDuration
        }
        return CMTime(
            seconds: maximumDurationSeconds,
            preferredTimescale: max(sourceDuration.timescale, 600)
        )
    }
}

private enum ProcessorError: Error {
    case invalidVideo
    case videoTooLong
    case fileTooLarge
    case insufficientStorage
    case encoderUnavailable
    case exportFailed

    func localizedMessage(bundle: Bundle) -> String {
        switch self {
        case .invalidVideo:
            String(localized: "error.invalidVideo", bundle: bundle)
        case .videoTooLong:
            String(localized: "error.videoTooLong", bundle: bundle)
        case .fileTooLarge:
            String(localized: "error.fileTooLarge", bundle: bundle)
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
    private var liveEntities: [MaskEntity]

    init(options: ProcessingOptions) {
        self.options = options
        liveEntities = options.maskEntities
        asciiGlyphTiles = options.style == .ascii
            ? Self.makeASCIIGlyphTiles(
                cellSize: CGFloat(options.strength),
                foreground: options.asciiForeground
            )
            : []
    }

    /// Latest auto-detected entities after a render or `syncEntities` pass.
    var currentEntities: [MaskEntity] {
        lock.lock()
        defer { lock.unlock() }
        return liveEntities
    }

    func warmUp() async {
        _ = context.createCGImage(CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)), from: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    /// Updates entity association from a still frame without applying effects.
    @discardableResult
    func syncEntities(from image: CIImage) -> [MaskEntity] {
        lock.lock()
        defer { lock.unlock() }
        let prepared = detectSubjects(in: image, extent: image.extent)
        liveEntities = MaskEntityAssociation.associate(
            existing: liveEntities.filter { options.subjects.contains($0.kind) },
            detections: prepared.map(\.association)
        )
        return liveEntities
    }

    func render(
        _ sourceImage: CIImage,
        at compositionTime: CMTime = .zero,
        renderSize: CGSize? = nil,
        externalMask: CIImage? = nil
    ) -> CIImage {
        let source = Self.scaledImage(sourceImage, to: renderSize)
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
            // nil is intentional when every entity is disabled or nothing is found.
            cachedMask = subjectMask(for: source, extent: extent)
        }
        let timeSeconds = compositionTime.seconds.isFinite
            ? compositionTime.seconds
            : 0
        let trackMask = maskTrackMask(at: timeSeconds, extent: extent)
        let detectedAndManualMask = Self.combinedMask(
            cachedMask,
            trackMask,
            extent: extent
        )
        guard var mask = Self.combinedMask(
            detectedAndManualMask,
            externalMask,
            extent: extent
        ) else {
            return source
        }
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

    private struct PreparedDetection {
        let association: MaskEntityAssociation.Detection
        let mask: CIImage
    }

    private func subjectMask(for image: CIImage, extent: CGRect) -> CIImage? {
        let prepared = detectSubjects(in: image, extent: extent)
        liveEntities = MaskEntityAssociation.associate(
            existing: liveEntities.filter { options.subjects.contains($0.kind) },
            detections: prepared.map(\.association)
        )
        let activeCount = prepared.count
        var masks: [CIImage] = []
        for index in 0..<activeCount where liveEntities[index].isEnabled {
            masks.append(prepared[index].mask)
        }
        guard var combined = masks.first else { return nil }
        for mask in masks.dropFirst() {
            combined = mask.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: combined
            ])
        }
        return combined.cropped(to: extent)
    }

    private func detectSubjects(in image: CIImage, extent: CGRect) -> [PreparedDetection] {
        var prepared: [PreparedDetection] = []
        if options.subjects.contains(.person) {
            prepared += personDetections(for: image, extent: extent)
        }
        if options.subjects.contains(.face) {
            prepared += faceDetections(for: image, extent: extent)
        }
        if options.subjects.contains(.pet) {
            prepared += petDetections(for: image, extent: extent)
        }
        return prepared
    }

    private func personDetections(for image: CIImage, extent: CGRect) -> [PreparedDetection] {
        let instanceRequest = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        if (try? handler.perform([instanceRequest])) != nil,
           let observation = instanceRequest.results?.first,
           !observation.allInstances.isEmpty {
            var detections: [PreparedDetection] = []
            for instance in observation.allInstances {
                guard instance > 0 else { continue }
                guard let buffer = try? observation.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instance),
                    from: handler
                ) else { continue }
                let mask = scaledMask(from: buffer, to: extent)
                guard let rect = normalizedBounds(of: mask, extent: extent),
                      rect.width * rect.height <= 0.95,
                      rect.width * rect.height > 0.002 else {
                    continue
                }
                detections.append(
                    PreparedDetection(
                        association: .init(
                            kind: .person,
                            source: .detectedPerson,
                            rect: rect
                        ),
                        mask: mask
                    )
                )
            }
            if !detections.isEmpty {
                return detections
            }
        }

        // Semantic whole-frame person mask as a single entity when instances fail.
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = options.quality == .fast
            ? .fast
            : (options.quality == .precise ? .accurate : .balanced)
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up)
                .perform([segmentation])
            if let buffer = segmentation.results?.first?.pixelBuffer {
                var semanticMask = scaledMask(from: buffer, to: extent)
                if options.quality == .precise,
                   let foregroundMask = foregroundInstanceMask(for: image, extent: extent) {
                    let semanticSafety = semanticMask
                        .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 6])
                        .cropped(to: extent)
                    semanticMask = foregroundMask
                        .applyingFilter("CIMinimumCompositing", parameters: [
                            kCIInputBackgroundImageKey: semanticSafety
                        ])
                        .cropped(to: extent)
                }
                if let rect = normalizedBounds(of: semanticMask, extent: extent),
                   rect.width * rect.height > 0.002 {
                    return [
                        PreparedDetection(
                            association: .init(
                                kind: .person,
                                source: .detectedPerson,
                                rect: rect
                            ),
                            mask: semanticMask
                        )
                    ]
                }
            }
        } catch {
            // Fall through to geometry.
        }

        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let faces = VNDetectFaceRectanglesRequest()
        configureCPU(faces)
        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up)
                .perform([humans, faces])
            let humanBoxes = (humans.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map(\.boundingBox)
            if !humanBoxes.isEmpty {
                return humanBoxes.compactMap { box in
                    guard let mask = boxMask(for: [box], extent: extent, padding: 0.025) else {
                        return nil
                    }
                    return PreparedDetection(
                        association: .init(
                            kind: .person,
                            source: .detectedPerson,
                            rect: NormalizedVideoRect(visionBoundingBox: box)
                        ),
                        mask: mask
                    )
                }
            }
            let faceBoxes = (faces.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map(\.boundingBox)
            return faceBoxes.compactMap { box in
                guard let mask = ellipseMask(for: [box], extent: extent) else { return nil }
                return PreparedDetection(
                    association: .init(
                        kind: .person,
                        source: .detectedPerson,
                        rect: NormalizedVideoRect(visionBoundingBox: box).expandedForFaceCoverage()
                    ),
                    mask: mask
                )
            }
        } catch {
            return []
        }
    }

    private func faceDetections(for image: CIImage, extent: CGRect) -> [PreparedDetection] {
        let request = VNDetectFaceRectanglesRequest()
        configureCPU(request)
        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up)
                .perform([request])
            let boxes = (request.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map(\.boundingBox)
            return boxes.compactMap { box in
                guard let mask = ellipseMask(for: [box], extent: extent) else { return nil }
                return PreparedDetection(
                    association: .init(
                        kind: .face,
                        source: .detectedFace,
                        rect: NormalizedVideoRect(visionBoundingBox: box).expandedForFaceCoverage()
                    ),
                    mask: mask
                )
            }
        } catch {
            return []
        }
    }

    private func petDetections(for image: CIImage, extent: CGRect) -> [PreparedDetection] {
        let request = VNRecognizeAnimalsRequest()
        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up)
                .perform([request])
            let boxes = (request.results ?? [])
                .filter { $0.confidence >= 0.35 }
                .map(\.boundingBox)
            return boxes.compactMap { box in
                let mask = foregroundInstanceMask(
                    for: image,
                    extent: extent,
                    matching: [box]
                ) ?? boxMask(for: [box], extent: extent, padding: 0.025)
                guard let mask else { return nil }
                return PreparedDetection(
                    association: .init(
                        kind: .pet,
                        source: .detectedPet,
                        rect: NormalizedVideoRect(visionBoundingBox: box)
                    ),
                    mask: mask
                )
            }
        } catch {
            return []
        }
    }

    private func configureCPU(_ request: VNRequest) {
        if let stageDevices = try? request.supportedComputeStageDevices {
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

    /// Approximate display-normalized bounds from a white-on-black mask.
    private func normalizedBounds(of mask: CIImage, extent: CGRect) -> NormalizedVideoRect? {
        let width = 64
        let height = max(1, Int((extent.height / max(extent.width, 1)) * CGFloat(width)))
        let render = CGRect(x: 0, y: 0, width: width, height: height)
        let scaled = mask
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / extent.width,
                y: CGFloat(height) / extent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: -extent.minX * CGFloat(width) / extent.width,
                y: -extent.minY * CGFloat(height) / extent.height
            ))
        guard let cgImage = context.createCGImage(scaled, from: render),
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if bytes[offset] > 40 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // cgImage rows are top-to-bottom; display space is also top-left.
        return NormalizedVideoRect(
            x: Double(minX) / Double(width),
            y: Double(minY) / Double(height),
            width: Double(maxX - minX + 1) / Double(width),
            height: Double(maxY - minY + 1) / Double(height)
        )
    }

    private static func combinedMask(
        _ first: CIImage?,
        _ second: CIImage?,
        extent: CGRect
    ) -> CIImage? {
        switch (first, second) {
        case let (first?, second?):
            return second.applyingFilter(
                "CIMaximumCompositing",
                parameters: [kCIInputBackgroundImageKey: first]
            ).cropped(to: extent)
        case let (first?, nil):
            return first.cropped(to: extent)
        case let (nil, second?):
            return second.cropped(to: extent)
        case (nil, nil):
            return nil
        }
    }

    private func maskTrackMask(
        at timeSeconds: TimeInterval,
        extent: CGRect
    ) -> CIImage? {
        let activeTracks = options.maskTracks.compactMap { track -> (MaskTrackShape, CGRect)? in
            guard let normalizedRect = track.rect(at: timeSeconds),
                  !normalizedRect.isEmpty else {
                return nil
            }
            return (
                track.shape,
                normalizedRect.rect(inCoreImageExtent: extent)
            )
        }
        guard !activeTracks.isEmpty else { return nil }

        var mask = CIImage(color: .black).cropped(to: extent)
        for (shape, rect) in activeTracks {
            let shapeMask: CIImage
            switch shape {
            case .rectangle:
                shapeMask = CIImage(color: .white).cropped(to: rect)
            case .ellipse:
                shapeMask = Self.ellipseMask(in: rect, extent: extent)
            }
            mask = shapeMask.applyingFilter(
                "CIMaximumCompositing",
                parameters: [kCIInputBackgroundImageKey: mask]
            )
        }
        return mask.cropped(to: extent)
    }

    private static func ellipseMask(in rect: CGRect, extent: CGRect) -> CIImage {
        CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: 0.5, y: 0.5),
                "inputRadius0": 0.48,
                "inputRadius1": 0.5,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ]
        )!.outputImage!
            .transformed(by: CGAffineTransform(
                scaleX: rect.width,
                y: rect.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: rect.minX,
                y: rect.minY
            ))
            .cropped(to: extent)
    }

    private static func scaledImage(_ source: CIImage, to renderSize: CGSize?) -> CIImage {
        guard let renderSize,
              renderSize.width > 0,
              renderSize.height > 0 else {
            return source
        }
        let target = CGRect(origin: .zero, size: renderSize)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return source }
        let scale = min(
            target.width / extent.width,
            target.height / extent.height
        )
        if abs(scale - 1) < 0.001,
           abs(extent.minX) < 0.001,
           abs(extent.minY) < 0.001 {
            return source.cropped(to: target)
        }
        let normalized = source.transformed(
            by: CGAffineTransform(
                translationX: -extent.minX,
                y: -extent.minY
            )
        )
        let scaled = normalized.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let offset = CGAffineTransform(
            translationX: (target.width - scaled.extent.width) / 2,
            y: (target.height - scaled.extent.height) / 2
        )
        return scaled
            .transformed(by: offset)
            .cropped(to: target)
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
        let background = options.asciiBackground
        var result = CIImage(color: CIColor(
            red: background.r,
            green: background.g,
            blue: background.b,
            alpha: background.a
        ))
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

    private static func makeASCIIGlyphTiles(
        cellSize: CGFloat,
        foreground: EffectRGBA
    ) -> [CIImage] {
        // Same light-to-dark ramp used by the web editor.
        let glyphs = Array(" .,:;irsXA253hMHGS#9B&@").map(String.init)
        let side = max(8, ceil(cellSize))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let font = UIFont.monospacedSystemFont(ofSize: side * 0.82, weight: .bold)
        let glyphColor = UIColor(
            red: foreground.r,
            green: foreground.g,
            blue: foreground.b,
            alpha: foreground.a
        )

        return glyphs.compactMap { glyph in
            let image = UIGraphicsImageRenderer(
                size: CGSize(width: side, height: side),
                format: format
            ).image { _ in
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: glyphColor
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
