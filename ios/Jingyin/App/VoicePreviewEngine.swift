import AVFoundation
import Combine

@MainActor
final class VoicePreviewEngine: ObservableObject {
    @Published private(set) var previewUnsupportedMessage: String?
    @Published private(set) var isPreparing = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
    private var preparedAudioURL: URL?
    private var preparationTask: Task<URL, Error>?
    private var sourceURL: URL?
    private var isPrepared = false
    private var graphConnected = false

    init() {
        timePitch.rate = 1
        engine.attach(playerNode)
        engine.attach(timePitch)
    }

    func configure(sourceURL: URL, semitones: Int) {
        if self.sourceURL != sourceURL {
            stop(unload: true)
            self.sourceURL = sourceURL
            isPrepared = false
            previewUnsupportedMessage = nil
        }
        setPitch(semitones)
    }

    func setPitch(_ semitones: Int) {
        timePitch.pitch = Float(VoicePitchStore.clamp(semitones)) * 100
    }

    func prepare() async -> Bool {
        await prepareIfNeeded()
    }

    func sync(at seconds: TimeInterval, playing: Bool) async {
        guard await prepareIfNeeded() else { return }
        guard let audioFile else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        guard startFrame < audioFile.length else {
            playerNode.stop()
            return
        }

        let remaining = AVAudioFrameCount(audioFile.length - startFrame)
        playerNode.stop()
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: remaining,
            at: nil,
            completionCallbackType: .dataPlayedBack,
            completionHandler: nil
        )

        startEngineIfNeeded()
        if playing {
            playerNode.play()
        } else {
            playerNode.pause()
        }
    }

    func pause() {
        playerNode.pause()
    }

    func stop(unload: Bool = false) {
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        if unload {
            preparationTask?.cancel()
            preparationTask = nil
            disconnectGraph()
            audioFile = nil
            if let preparedAudioURL {
                try? FileManager.default.removeItem(at: preparedAudioURL)
                self.preparedAudioURL = nil
            }
            isPrepared = false
            isPreparing = false
            sourceURL = nil
        }
    }

    private func prepareIfNeeded() async -> Bool {
        if isPrepared { return true }
        guard let sourceURL else { return false }
        let requestedSourceURL = sourceURL
        isPreparing = true
        previewUnsupportedMessage = nil
        var readableURLForCleanup: URL?

        do {
            if preparationTask == nil {
                preparationTask = Task {
                    try await VoicePitchExporter.extractAudioFile(from: requestedSourceURL)
                }
            }
            guard let task = preparationTask else { return false }
            let readableURL = try await task.value
            if isPrepared {
                return true
            }
            guard self.sourceURL == requestedSourceURL else {
                try? FileManager.default.removeItem(at: readableURL)
                isPreparing = false
                return false
            }
            preparationTask = nil
            readableURLForCleanup = readableURL

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)

            let file = try AVAudioFile(forReading: readableURL)
            let format = file.processingFormat
            disconnectGraph()
            engine.connect(playerNode, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            graphConnected = true
            audioFile = file
            preparedAudioURL = readableURL
            readableURLForCleanup = nil
            isPrepared = true
            isPreparing = false
            previewUnsupportedMessage = nil
            return true
        } catch {
            preparationTask = nil
            isPreparing = false
            if let readableURLForCleanup {
                try? FileManager.default.removeItem(at: readableURLForCleanup)
            }
            if error is CancellationError {
                return false
            }
            previewUnsupportedMessage = "当前无法实时试听变音"
            isPrepared = false
            audioFile = nil
            return false
        }
    }

    private func disconnectGraph() {
        guard graphConnected else { return }
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(timePitch)
        graphConnected = false
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            previewUnsupportedMessage = "当前无法实时试听变音"
        }
    }
}
