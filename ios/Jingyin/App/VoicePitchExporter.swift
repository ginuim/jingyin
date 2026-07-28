@preconcurrency import AVFoundation

enum VoicePitchExporter {
    enum ExportError: Error {
        case noAudioTrack
        case renderFailed
        case muxFailed

        func localizedMessage(bundle: Bundle) -> String {
            switch self {
            case .noAudioTrack:
                String(localized: "error.noAudioTrack", bundle: bundle)
            case .renderFailed:
                String(localized: "error.voiceRenderFailed", bundle: bundle)
            case .muxFailed:
                String(localized: "error.voiceMuxFailed", bundle: bundle)
            }
        }
    }

    /// Renders pitch-shifted audio from `sourceURL` into a temporary m4a file.
    static func renderPitchedAudio(
        from sourceURL: URL,
        semitones: Int,
        maximumDuration: TimeInterval? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let extracted = try await extractAudioFile(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: extracted) }

        let input = try AVAudioFile(forReading: extracted)
        let format = input.processingFormat
        guard input.length > 0 else { throw ExportError.noAudioTrack }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-pitch-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = 1
        timePitch.pitch = Float(VoicePitchStore.clamp(semitones)) * 100

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1

        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
        try engine.start()
        // Passing no completion handler selects Swift's async overlay, which
        // waits for playback to finish. Playback only starts on the next line,
        // so awaiting it here deadlocks the export at 68%.
        player.scheduleFile(
            input,
            at: nil,
            completionCallbackType: .dataConsumed,
            completionHandler: nil
        )
        player.play()

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 128_000
        ]
        let output = try AVAudioFile(forWriting: outputURL, settings: settings)

        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames)!
        let total = max(engine.manualRenderingSampleTime, 1)
        // TimePitch keeps duration ~same; render until input drained + short tail.
        let requestedFrames = maximumDuration.map {
            AVAudioFramePosition($0 * format.sampleRate)
        }
        let inputFrames = min(input.length, requestedFrames ?? input.length)
        let targetFrames = inputFrames + AVAudioFramePosition(format.sampleRate * 0.25)
        var consecutiveEmptyRenders = 0

        while engine.manualRenderingSampleTime < targetFrames {
            try Task.checkCancellation()
            let frames = min(maxFrames, AVAudioFrameCount(targetFrames - engine.manualRenderingSampleTime))
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                consecutiveEmptyRenders = 0
                if buffer.frameLength > 0 {
                    try output.write(from: buffer)
                }
            case .insufficientDataFromInputNode:
                consecutiveEmptyRenders += 1
                if !player.isPlaying {
                    break
                }
                guard consecutiveEmptyRenders < 32 else {
                    throw ExportError.renderFailed
                }
                await Task.yield()
            case .cannotDoInCurrentContext:
                throw ExportError.renderFailed
            case .error:
                throw ExportError.renderFailed
            @unknown default:
                throw ExportError.renderFailed
            }
            let rendered = Double(engine.manualRenderingSampleTime)
            progress?(min(1, rendered / Double(max(targetFrames, total))))
            if status == .insufficientDataFromInputNode && !player.isPlaying {
                break
            }
        }

        player.stop()
        engine.stop()
        progress?(1)
        return outputURL
    }

    static func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.muxFailed
        }
        let duration = try await videoAsset.load(.duration)
        let videoCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        try videoCompositionTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        if let preferred = try? await videoTrack.load(.preferredTransform) {
            videoCompositionTrack?.preferredTransform = preferred
        }

        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
            let audioDuration = try await audioAsset.load(.duration)
            let insertDuration = CMTimeMinimum(duration, audioDuration)
            let audioCompositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try audioCompositionTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: audioTrack,
                at: .zero
            )
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ExportError.muxFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else {
            // Some source containers reject passthrough; fall back to re-encoding.
            guard let fallback = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw session.error ?? ExportError.muxFailed
            }
            try? FileManager.default.removeItem(at: outputURL)
            fallback.outputURL = outputURL
            fallback.outputFileType = .mp4
            await fallback.export()
            guard fallback.status == .completed else {
                throw fallback.error ?? ExportError.muxFailed
            }
            return
        }
    }

    /// Produces a temporary file that `AVAudioFile` can read. Video containers
    /// are opened directly when possible and otherwise exported as M4A.
    static func extractAudioFile(from sourceURL: URL) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ExportError.noAudioTrack }

        // Prefer opening the container directly when AVAudioFile can decode it.
        if let direct = try? AVAudioFile(forReading: sourceURL), direct.length > 0 {
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("jingyin-audio-src-\(UUID().uuidString).\(sourceURL.pathExtension)")
            try? FileManager.default.removeItem(at: copyURL)
            try FileManager.default.copyItem(at: sourceURL, to: copyURL)
            return copyURL
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-audio-extract-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.renderFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        await session.export()
        try Task.checkCancellation()
        guard session.status == .completed else {
            throw session.error ?? ExportError.renderFailed
        }
        return outputURL
    }
}
