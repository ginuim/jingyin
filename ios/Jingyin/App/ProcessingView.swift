import AVKit
import Photos
import SwiftUI

struct ProcessingView: View {
    let videoURL: URL
    let options: ProcessingOptions
    let access: ExportAccess
    @EnvironmentObject private var localization: LocalizationManager
    @StateObject private var processor = VideoProcessor()
    @State private var showShare = false
    @State private var saved = false
    @State private var processingTask: Task<Void, Never>?
    /// Must outlive body redraws. Creating AVPlayer inside `body` tears the
    /// previous player down on every state change (e.g. tapping Save) and crashes.
    @State private var previewPlayer: AVPlayer?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            stageIcon
            VStack(spacing: 10) {
                Text(processor.stage.title(bundle: localization.bundle))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Int(processor.progress * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: processor.progress)
                    .tint(.mint)
                if processor.isRunning {
                    Text(remainingTimeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let advisory = processor.advisory {
                    Label(advisory, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 32)

            if case let .failed(message) = processor.stage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                Button(localization.t("processing.retry")) { start() }
                    .buttonStyle(.borderedProminent)
            }

            if let previewPlayer {
                ControlledVideoPlayer(player: previewPlayer) {
                    VideoPlayer(player: previewPlayer)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal)

                HStack {
                    Button {
                        Task { saved = await processor.saveToPhotos() }
                    } label: {
                        Label(
                            saved ? localization.t("processing.saved") : localization.t("processing.save"),
                            systemImage: saved ? "checkmark" : "square.and.arrow.down"
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showShare = true
                    } label: {
                        Label(localization.t("processing.share"), systemImage: "square.and.arrow.up")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
            if processor.isRunning {
                Button(localization.t("processing.cancel"), role: .destructive) {
                    processingTask?.cancel()
                    processor.cancel()
                }
            }
        }
        .padding()
        .background(Color(red: 0.035, green: 0.065, blue: 0.07))
        .navigationTitle(localization.t("processing.title"))
        .navigationBarBackButtonHidden(processor.isRunning)
        .task { start() }
        .onChange(of: processor.outputURL) { _, url in
            previewPlayer?.pause()
            previewPlayer = url.map { AVPlayer(url: $0) }
            saved = false
        }
        .onDisappear {
            processingTask?.cancel()
            processor.cancel()
            previewPlayer?.pause()
            previewPlayer = nil
        }
        .sheet(isPresented: $showShare) {
            if let output = processor.outputURL {
                ShareSheet(items: [output])
            }
        }
    }

    private var stageIcon: some View {
        Image(systemName: processor.outputURL == nil ? "gearshape.2.fill" : "checkmark.shield.fill")
            .font(.system(size: 56))
            .foregroundStyle(.mint)
            .symbolEffect(.pulse, options: .repeating, isActive: processor.isRunning)
    }

    private var remainingTimeText: String {
        guard let remaining = processor.estimatedRemainingSeconds else {
            return localization.t("processing.estimating")
        }
        let totalSeconds = max(1, Int(remaining.rounded(.up)))
        if totalSeconds >= 60 {
            return localization.format(
                "processing.remainingMinutes",
                Int64(totalSeconds / 60),
                Int64(totalSeconds % 60)
            )
        }
        return localization.format(
            "processing.remainingSeconds",
            Int64(totalSeconds)
        )
    }

    private func start() {
        processingTask?.cancel()
        let bundle = localization.bundle
        processingTask = Task {
            await processor.process(
                sourceURL: videoURL,
                options: options,
                access: access,
                bundle: bundle
            )
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
