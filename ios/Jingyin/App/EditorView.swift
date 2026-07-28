import AVKit
import SwiftUI

struct EditorView: View {
    let videoURL: URL
    @State private var player: AVPlayer
    @State private var options = ProcessingOptions()
    @State private var showProcessing = false
    @State private var previewGeneration = 0

    init(videoURL: URL) {
        self.videoURL = videoURL
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
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

                Button {
                    player.pause()
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
        .task(id: options) {
            await applyPreview()
        }
        .onDisappear { player.pause() }
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

            OptionSection(title: "处理档位", systemImage: "speedometer") {
                Picker("处理档位", selection: $options.quality) {
                    ForEach(QualityMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            OptionSection(title: "声音", systemImage: "speaker.wave.2") {
                Picker("声音", selection: $options.audio) {
                    ForEach(AudioMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
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
        if wasPlaying {
            player.play()
        }
    }
}

private struct OptionSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
