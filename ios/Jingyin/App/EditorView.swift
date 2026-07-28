import AVFoundation
import AVKit
import SwiftUI

struct EditorView: View {
    let videoURL: URL
    @State private var player: AVPlayer
    @State private var options = ProcessingOptions()
    @State private var showProcessing = false
    @State private var previewGeneration = 0
    @StateObject private var voicePreview = VoicePreviewEngine()
    @State private var statusObserver: NSKeyValueObservation?
    @State private var jumpObserver: NSObjectProtocol?

    init(videoURL: URL) {
        self.videoURL = videoURL
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Restored original preview surface + composition path.
                VideoPlayer(player: player)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .topTrailing) {
                        Label("效果预览", systemImage: "eye.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(10)
                    }

                settings

                if let message = voicePreview.previewUnsupportedMessage, options.audio == .voice {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    player.pause()
                    voicePreview.stop(unload: true)
                    showProcessing = true
                } label: {
                    Label("开始本地处理", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .foregroundStyle(.black)
            }
            .padding()
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.07))
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showProcessing) {
            ProcessingView(videoURL: videoURL, options: options)
        }
        .task(id: videoEffectToken) {
            await applyPreview()
        }
        .onAppear {
            installPlayerObservers()
            applyAudioMode()
        }
        .onChange(of: options.audio) { _, _ in
            applyAudioMode()
        }
        .onChange(of: options.voicePitch) { _, pitch in
            VoicePitchStore.save(pitch)
            voicePreview.setPitch(pitch)
        }
        .onDisappear {
            removePlayerObservers()
            player.pause()
            voicePreview.stop(unload: true)
        }
    }

    /// Exclude audio/pitch so voice slider does not rebuild the mask composition.
    private var videoEffectToken: String {
        let subjects = options.subjects.map(\.rawValue).sorted().joined(separator: ",")
        return "\(options.quality.rawValue)|\(options.scope.rawValue)|\(options.style.rawValue)|\(options.strength)|\(subjects)"
    }

    private var settings: some View {
        VStack(spacing: 18) {
            OptionSection(title: "遮盖范围", systemImage: "viewfinder") {
                Picker("遮盖范围", selection: $options.scope) {
                    ForEach(MaskScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if options.scope != .full {
                OptionSection(title: "识别主体", systemImage: "person.2.crop.square.stack") {
                    HStack(spacing: 10) {
                        ForEach(SubjectKind.allCases) { subject in
                            Button {
                                toggle(subject)
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: subject.icon)
                                    Text(subject.rawValue)
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    options.subjects.contains(subject) ? Color.mint.opacity(0.9) : .white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .foregroundStyle(options.subjects.contains(subject) ? .black : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                OptionSection(title: "处理档位", systemImage: "speedometer") {
                    Picker("处理档位", selection: $options.quality) {
                        ForEach(QualityMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            OptionSection(title: "画面效果", systemImage: "circle.lefthalf.filled") {
                Picker("画面效果", selection: $options.style) {
                    ForEach(EffectStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: options.style) { _, style in
                    switch style {
                    case .blur: options.strength = 32
                    case .pixel: options.strength = 18
                    case .ascii: options.strength = 14
                    }
                }
                Slider(value: $options.strength, in: strengthRange) {
                    Text("强度")
                } minimumValueLabel: {
                    Text("弱")
                } maximumValueLabel: {
                    Text("强")
                }
                Text(strengthDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            OptionSection(
                title: "声音处理",
                systemImage: "speaker.wave.2",
                meta: options.audioMeta
            ) {
                Picker("声音处理", selection: $options.audio) {
                    ForEach(AudioMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if options.audio == .voice {
                    HStack {
                        Text("低")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(options.voicePitch) },
                                set: { options.voicePitch = Int($0.rounded()) }
                            ),
                            in: Double(VoicePitchStore.range.lowerBound)...Double(VoicePitchStore.range.upperBound),
                            step: 1
                        )
                        Text("高")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("真正改变音调，不改变语速；播放时拖动可实时试听。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggle(_ subject: SubjectKind) {
        if options.subjects.contains(subject) {
            guard options.subjects.count > 1 else { return }
            options.subjects.remove(subject)
        } else {
            options.subjects.insert(subject)
        }
    }

    private var strengthRange: ClosedRange<Double> {
        switch options.style {
        case .blur: 4...64
        case .pixel: 6...48
        case .ascii: 8...30
        }
    }

    private var strengthDescription: String {
        switch options.style {
        case .blur: "模糊半径 \(Int(options.strength)) px"
        case .pixel: "像素块 \(Int(options.strength)) px"
        case .ascii: "黑白字符画 · 字符 \(Int(options.strength)) px"
        }
    }

    /// Exact preview composition path from the last known-good mask build.
    @MainActor
    private func applyPreview() async {
        previewGeneration += 1
        let generation = previewGeneration
        let wasPlaying = player.rate > 0
        let time = player.currentTime()
        let asset = AVURLAsset(url: videoURL)
        let processor = FrameEffectProcessor(options: options)
        await processor.warmUp()
        guard generation == previewGeneration, !Task.isCancelled else { return }

        let composition = AVVideoComposition(asset: asset) { request in
            request.finish(with: processor.render(request.sourceImage), context: nil)
        }
        guard generation == previewGeneration, !Task.isCancelled else { return }

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        player.replaceCurrentItem(with: item)
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        applyAudioMode()
        if wasPlaying {
            player.play()
        }
    }

    private func applyAudioMode() {
        switch options.audio {
        case .original:
            player.isMuted = false
            voicePreview.stop(unload: true)
        case .mute:
            player.isMuted = true
            voicePreview.stop(unload: true)
        case .voice:
            player.isMuted = true
            voicePreview.configure(sourceURL: videoURL, semitones: options.voicePitch)
            let seconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
            Task {
                await voicePreview.sync(at: seconds, playing: player.timeControlStatus == .playing)
            }
        }
    }

    private func installPlayerObservers() {
        removePlayerObservers()
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            Task { @MainActor in
                syncVoicePreview(with: player)
            }
        }
        jumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            Task { @MainActor in
                syncVoicePreview(with: player)
            }
        }
    }

    private func removePlayerObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let jumpObserver {
            NotificationCenter.default.removeObserver(jumpObserver)
            self.jumpObserver = nil
        }
    }

    private func syncVoicePreview(with player: AVPlayer) {
        guard options.audio == .voice else { return }
        let seconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        switch player.timeControlStatus {
        case .playing:
            Task { await voicePreview.sync(at: seconds, playing: true) }
        case .paused:
            voicePreview.pause()
        default:
            break
        }
    }
}

private struct OptionSection<Content: View>: View {
    let title: String
    let systemImage: String
    var meta: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer(minLength: 8)
                if let meta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            content
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
