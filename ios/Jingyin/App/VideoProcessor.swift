@preconcurrency import AVFoundation
import CoreImage
import Photos
import UIKit
import Vision

@MainActor
final class VideoProcessor: ObservableObject {
    @Published private(set) var stage: ProcessingStage = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var outputURL: URL?
    @Published private(set) var advisory: String?
    private var exportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?

    var isRunning: Bool {
        switch stage {
        case .reading, .loadingModel, .warmingUp, .analyzing, .encoding: true
        default: false
        }
    }

    func process(sourceURL: URL, options: ProcessingOptions) async {
        cancel()
        outputURL = nil
        advisory = nil
        progress = 0
        stage = .reading
        // Keep screen awake for the whole export; lock/sleep commonly yields
        // AVErrorOperationInterrupted ("The operation was interrupted").
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        do {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite, duration.seconds > 0 else {
                throw ProcessorError.invalidVideo
            }
            guard duration.seconds <= 300 else {
                throw ProcessorError.videoTooLong
            }
            let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= 1_000_000_000 else {
                throw ProcessorError.fileTooLarge
            }
            let capacity = try FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            guard capacity == 0 || capacity > Int64(max(fileSize * 2, 250_000_000)) else {
                throw ProcessorError.insufficientStorage
            }

            var effectiveOptions = options
            if options.quality == .precise && Self.shouldDowngradePreciseMode {
                effectiveOptions.quality = .balanced
                advisory = "设备当前资源紧张，已自动切换为均衡档。"
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

            switch effectiveOptions.audio {
            case .voice:
                try await exportWithVoicePitch(
                    asset: asset,
                    composition: composition,
                    sourceURL: sourceURL,
                    semitones: effectiveOptions.voicePitch,
                    destination: destination
                )
            case .original, .mute:
                guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
                    throw ProcessorError.encoderUnavailable
                }
                exportSession = session
                session.outputURL = destination
                session.outputFileType = .mp4
                session.videoComposition = composition
                if effectiveOptions.audio == .mute {
                    session.audioMix = try await Self.mutedAudioMix(for: asset)
                }

                progressTask = Task { [weak self, weak session] in
                    while let session, !Task.isCancelled {
                        let value = Double(session.progress)
                        self?.progress = 0.1 + value * 0.88
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }
                await session.export()
                progressTask?.cancel()
                exportSession = nil

                switch session.status {
                case .completed:
                    break
                case .cancelled:
                    throw CancellationError()
                default:
                    throw session.error ?? ProcessorError.exportFailed
                }
            }

            outputURL = destination
            progress = 1
            stage = .completed(destination)
        } catch is CancellationError {
            stage = .failed("处理已取消，可返回调整后重试。")
        } catch {
            stage = .failed(Self.message(for: error))
        }
    }

    func cancel() {
        progressTask?.cancel()
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
        sourceURL: URL,
        semitones: Int,
        destination: URL
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

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw ProcessorError.encoderUnavailable
        }
        exportSession = session
        session.outputURL = mutedVideoURL
        session.outputFileType = .mp4
        session.videoComposition = composition
        session.audioMix = try await Self.mutedAudioMix(for: asset)

        progressTask = Task { [weak self, weak session] in
            while let session, !Task.isCancelled {
                let value = Double(session.progress)
                self?.progress = 0.1 + value * 0.55
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        await session.export()
        progressTask?.cancel()
        exportSession = nil

        switch session.status {
        case .completed:
            break
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? ProcessorError.exportFailed
        }

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
            advisory = "视频无音轨，已按无声导出"
            try FileManager.default.copyItem(at: mutedVideoURL, to: destination)
        } catch let error as VoicePitchExporter.ExportError {
            throw error
        } catch {
            throw VoicePitchExporter.ExportError.renderFailed
        }
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

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "无法完成导出：\(error.localizedDescription)"
    }

    private static var shouldDowngradePreciseMode: Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        return ProcessInfo.processInfo.physicalMemory < 4_000_000_000
            || thermal == .serious
            || thermal == .critical
    }
}

private enum ProcessorError: LocalizedError {
    case invalidVideo
    case videoTooLong
    case fileTooLarge
    case insufficientStorage
    case encoderUnavailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidVideo: "视频无效或无法读取。"
        case .videoTooLong: "首版暂时支持最长 5 分钟的视频。"
        case .fileTooLarge: "首版暂时支持最大 1 GB 的视频文件。"
        case .insufficientStorage: "可用存储空间不足，请清理空间后重试。"
        case .encoderUnavailable: "当前设备没有可用的视频编码器。"
        case .exportFailed: "视频编码失败，请降低档位后重试。"
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

    private func foregroundInstanceMask(for image: CIImage, extent: CGRect) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                return nil
            }
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            return scaledMask(from: buffer, to: extent)
        } catch {
            return nil
        }
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
            return boxMask(
                for: observations.filter { $0.confidence >= 0.35 }.map(\.boundingBox),
                extent: extent,
                padding: 0.025
            )
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
