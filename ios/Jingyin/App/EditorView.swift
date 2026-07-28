import AVFoundation
import AVKit
import SwiftUI

struct EditorView: View {
    let videoURL: URL
    @EnvironmentObject private var localization: LocalizationManager
    @State private var player: AVPlayer
    @State private var options = ProcessingOptions()
    @State private var showProcessing = false
    @State private var showExportSettings = false
    @State private var sourceMetadata: SourceVideoMetadata?
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
                ControlledVideoPlayer(player: player) {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(alignment: .topTrailing) {
                            Label(localization.t("editor.previewBadge"), systemImage: "eye.fill")
                                .font(.caption.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(10)
                        }
                }

                settings

                if voicePreview.isPreparing, options.audio == .voice {
                    ProgressView(localization.t("editor.preparingVoice"))
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if voicePreview.isPreviewUnsupported, options.audio == .voice {
                    Label(localization.t("error.previewUnsupported"), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    player.pause()
                    voicePreview.stop(unload: true)
                    showExportSettings = true
                } label: {
                    Label(localization.t("editor.start"), systemImage: "wand.and.stars")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
        .navigationTitle(localization.t("editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showProcessing) {
            ProcessingView(videoURL: videoURL, options: options)
        }
        .sheet(isPresented: $showExportSettings) {
            ExportSettingsSheet(
                options: $options,
                metadata: sourceMetadata,
                onExport: {
                    showExportSettings = false
                    showProcessing = true
                }
            )
            .environmentObject(localization)
        }
        .task(id: videoEffectToken) {
            await applyPreview()
        }
        .task {
            await loadSourceMetadata()
        }
        .task {
            // Simulator smoke-test hook. It keeps long-video verification
            // repeatable without affecting normal launches.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-demoExportSettings") {
                while sourceMetadata == nil, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                showExportSettings = true
            } else if arguments.contains("-demoProcess") {
                options.scope = .full
                options.quality = .fast
                options.audio = .original
                options.exportResolution = .p480
                options.exportFrameRate = 24
                player.pause()
                showProcessing = true
            }
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
        let bundle = localization.bundle
        return VStack(spacing: 18) {
            OptionSection(title: localization.t("editor.scope"), systemImage: "viewfinder") {
                Picker(localization.t("editor.scope"), selection: $options.scope) {
                    ForEach(MaskScope.allCases) {
                        Text($0.title(bundle))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }

            if options.scope != .full {
                OptionSection(title: localization.t("editor.subjects"), systemImage: "person.2.crop.square.stack") {
                    HStack(spacing: 10) {
                        ForEach(SubjectKind.allCases) { subject in
                            Button {
                                toggle(subject)
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: subject.icon)
                                    Text(subject.title(bundle))
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
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

                OptionSection(title: localization.t("editor.quality"), systemImage: "speedometer") {
                    Picker(localization.t("editor.quality"), selection: $options.quality) {
                        ForEach(QualityMode.allCases) {
                            Text($0.title(bundle))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(options.quality.detail(bundle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            OptionSection(title: localization.t("editor.style"), systemImage: "circle.lefthalf.filled") {
                Picker(localization.t("editor.style"), selection: $options.style) {
                    ForEach(EffectStyle.allCases) {
                        Text($0.title(bundle))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .tag($0)
                    }
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
                    Text(localization.t("editor.strength"))
                } minimumValueLabel: {
                    Text(localization.t("editor.weak"))
                } maximumValueLabel: {
                    Text(localization.t("editor.strong"))
                }
                Text(strengthDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OptionSection(
                title: localization.t("editor.audio"),
                systemImage: "speaker.wave.2",
                meta: options.audioMeta(bundle: bundle)
            ) {
                Picker(localization.t("editor.audio"), selection: $options.audio) {
                    ForEach(AudioMode.allCases) {
                        Text($0.title(bundle))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)

                if options.audio == .voice {
                    HStack {
                        Text(localization.t("editor.pitchLow"))
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
                        Text(localization.t("editor.pitchHigh"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(localization.t("editor.pitchHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    @MainActor
    private func loadSourceMetadata() async {
        guard sourceMetadata == nil,
              let metadata = try? await SourceVideoMetadata.load(from: videoURL) else {
            return
        }
        sourceMetadata = metadata
        options.exportResolution = .defaultValue(for: metadata.shortEdge)
        options.exportFrameRate = metadata.defaultFrameRate
    }

    private var strengthRange: ClosedRange<Double> {
        switch options.style {
        case .blur: 4...64
        case .pixel: 6...48
        case .ascii: 8...30
        }
    }

    private var strengthDescription: String {
        let value = Int64(options.strength)
        switch options.style {
        case .blur:
            return localization.format("strength.blur", value)
        case .pixel:
            return localization.format("strength.pixel", value)
        case .ascii:
            return localization.format("strength.ascii", value)
        }
    }

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
        installPlayerObservers()
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
            Task {
                guard await voicePreview.prepare() else { return }
                let currentTime = player.currentTime().seconds
                let seconds = currentTime.isFinite ? currentTime : 0
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

private struct ExportSettingsSheet: View {
    @Binding var options: ProcessingOptions
    let metadata: SourceVideoMetadata?
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        NavigationStack {
            Group {
                if let metadata {
                    ScrollView {
                        VStack(spacing: 24) {
                            exportChoice(
                                title: localization.t("export.resolution"),
                                hint: localization.t("export.resolutionHint"),
                                values: metadata.availableResolutions,
                                selection: $options.exportResolution,
                                label: \.title
                            )
                            exportChoice(
                                title: localization.t("export.frameRate"),
                                hint: localization.t("export.frameRateHint"),
                                values: metadata.availableFrameRates,
                                selection: $options.exportFrameRate
                            ) { "\($0) fps" }

                            Label(
                                localization.t("export.speedHint"),
                                systemImage: "hare.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                } else {
                    ProgressView(localization.t("export.reading"))
                }
            }
            .navigationTitle(localization.t("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("export.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.t("export.start")) {
                        onExport()
                    }
                    .disabled(metadata == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func exportChoice<Value: Hashable>(
        title: String,
        hint: String,
        values: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        Text(label(value))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                selection.wrappedValue == value
                                    ? Color.mint
                                    : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(
                                selection.wrappedValue == value ? .black : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if let meta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
