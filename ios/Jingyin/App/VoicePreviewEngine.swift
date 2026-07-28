import AVFoundation
import Combine

@MainActor
final class VoicePreviewEngine: ObservableObject {
    @Published private(set) var previewUnsupportedMessage: String?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
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

    func sync(at seconds: TimeInterval, playing: Bool) async {
        guard prepareIfNeeded() else { return }
        guard let audioFile else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        guard startFrame < audioFile.length else {
            playerNode.stop()
            return
        }

        let remaining = AVAudioFrameCount(audioFile.length - startFrame)
        playerNode.stop()
        await playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: remaining,
            at: nil,
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
            disconnectGraph()
            audioFile = nil
            isPrepared = false
            sourceURL = nil
        }
    }

    private func prepareIfNeeded() -> Bool {
        if isPrepared { return true }
        guard let sourceURL else { return false }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)

            let file = try AVAudioFile(forReading: sourceURL)
            let format = file.processingFormat
            disconnectGraph()
            engine.connect(playerNode, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            graphConnected = true
            audioFile = file
            isPrepared = true
            previewUnsupportedMessage = nil
            return true
        } catch {
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
