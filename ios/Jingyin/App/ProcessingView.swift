import AVKit
import Photos
import SwiftUI

struct ProcessingView: View {
    let videoURL: URL
    let options: ProcessingOptions
    let access: ExportAccess
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @StateObject private var processor = VideoProcessor()
    @State private var showShare = false
    @State private var saved = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var processingTask: Task<Void, Never>?
    @State private var showCancelConfirmation = false
    @State private var playConfetti = false
    /// Must outlive body redraws. Creating AVPlayer inside `body` tears the
    /// previous player down on every state change (e.g. tapping Save) and crashes.
    @State private var previewPlayer: AVPlayer?

    var body: some View {
        ZStack {
            Group {
                if let previewPlayer {
                    resultContent(player: previewPlayer)
                } else {
                    processingContent
                }
            }

            if playConfetti {
                ConfettiBurstView {
                    playConfetti = false
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(AppPalette.primaryText)
        .background(AppPalette.background.ignoresSafeArea())
        .navigationTitle(
            localization.t(
                previewPlayer == nil ? "processing.title" : "processing.resultTitle"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(processor.isRunning || isSaving)
        .task {
            start()
#if DEBUG
            if let delay = demoCancellationDelay {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, processor.isRunning else { return }
                cancelAndDismiss()
            } else if let delay = demoRetryDelay {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if case .failed = processor.stage {
                    start()
                }
            } else if let delay = demoRestartDelay {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, processor.isRunning else { return }
                start()
            }
#endif
        }
        .onAppear {
            MediaPlaybackSession.activate()
        }
        .onChange(of: processor.outputURL) { _, url in
            if url != nil {
                // Completion wins if it lands while the cancellation alert is
                // open. Dismiss the stale alert so it cannot discard a valid result.
                showCancelConfirmation = false
            }
            previewPlayer?.pause()
            previewPlayer = url.map { AVPlayer(url: $0) }
            playConfetti = url != nil
            saved = false
            isSaving = false
        }
        .onDisappear {
            processingTask?.cancel()
            processor.discardOutput()
            previewPlayer?.pause()
            previewPlayer = nil
            MediaPlaybackSession.deactivate()
        }
        .sheet(isPresented: $showShare) {
            if let output = processor.outputURL {
                ShareSheet(items: [output])
            }
        }
        .alert(
            localization.t("photo.saveFailed"),
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button(localization.t("common.ok"), role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .alert(
            localization.t("processing.confirmCancelTitle"),
            isPresented: $showCancelConfirmation
        ) {
            Button(localization.t("common.cancel"), role: .cancel) {}
            Button(localization.t("processing.cancel"), role: .destructive) {
                cancelAndDismiss()
            }
        } message: {
            Text(localization.t("processing.confirmCancelMessage"))
        }
    }

    private var processingContent: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 18)

            processingPreview

            VStack(spacing: 10) {
                Text(processor.stage.title(bundle: localization.bundle))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Int(processor.progress * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: processor.progress))
                    .animation(.easeInOut(duration: 0.2), value: processor.progress)
                if processor.isRunning {
                    Text(remainingTimeText)
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryText)
                        .monospacedDigit()
                }
                if let advisory = processor.advisory {
                    Label(advisory, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 32)

            if case let .failed(message) = processor.stage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(AppPalette.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                Button(localization.t("processing.retry")) { start() }
                    .buttonStyle(PrimaryButtonStyle())
            }

            Spacer(minLength: 18)
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            if processor.isRunning {
                Button(localization.t("processing.cancel"), role: .destructive) {
                    showCancelConfirmation = true
                }
                .buttonStyle(TextButtonStyle(role: .destructive))
                .padding(.bottom, 8)
            }
        }
    }

    private var processingPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.mediaCanvas)

            if let image = processor.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: processor.previewImage)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppPalette.accent.primary)
            }

            VStack {
                Spacer()
                ProgressView(value: processor.progress)
                    .tint(AppPalette.accent.primary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppPalette.divider.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(processor.stage.title(bundle: localization.bundle))
        .accessibilityValue("\(Int(processor.progress * 100))%")
    }

    private func resultContent(player: AVPlayer) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                resultHeader

                ControlledVideoPlayer(
                    player: player,
                    showsCentralPlayButton: true
                ) {
                    BareVideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(AppPalette.mediaCanvas)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }

                resultActions
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
    }

    private var resultHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppPalette.accent.softFill)
                Circle()
                    .stroke(AppPalette.accent.primary, lineWidth: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppPalette.accent.primary)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text(processor.stage.title(bundle: localization.bundle))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)

            Text(localization.t("processing.completedSubtitle"))
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
    }

    private var resultActions: some View {
        VStack(spacing: 14) {
            Button(action: saveOutput) {
                ZStack {
                    Label(
                        saved
                            ? localization.t("processing.savedAndViewPhotos")
                            : localization.t("processing.save"),
                        systemImage: saved
                            ? "photo.on.rectangle.angled"
                            : "square.and.arrow.down"
                    )
                    .opacity(isSaving ? 0 : 1)

                    if isSaving {
                        ProgressView()
                            .tint(AppPalette.accent.foreground)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving)

            HStack(spacing: 12) {
                secondaryAction(
                    title: localization.t("processing.share"),
                    systemImage: "square.and.arrow.up"
                ) {
                    showShare = true
                }

                secondaryAction(
                    title: localization.t("processing.reprocess"),
                    systemImage: "arrow.clockwise"
                ) {
                    dismiss()
                }
            }
            .disabled(isSaving)
        }
    }

    private func secondaryAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private func saveOutput() {
        guard !isSaving else { return }
        if saved {
            PhotoLibraryNavigator.openPhotos()
            return
        }
        isSaving = true
        saveErrorMessage = nil
        Task {
            if await processor.saveToPhotos() {
                saved = true
            } else {
                saveErrorMessage = localization.t("photo.saveFailedDetail")
            }
            isSaving = false
        }
    }

    private func cancelAndDismiss() {
        processingTask?.cancel()
        processor.cancel()
        dismiss()
    }

#if DEBUG
    private var demoCancellationDelay: TimeInterval? {
        demoDelay(for: "-demoCancelAfter")
    }

    private var demoRetryDelay: TimeInterval? {
        demoDelay(for: "-demoRetryAfter")
    }

    private var demoRestartDelay: TimeInterval? {
        demoDelay(for: "-demoRestartAfter")
    }

    private func demoDelay(for argument: String) -> TimeInterval? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1),
              let seconds = TimeInterval(arguments[index + 1]),
              seconds >= 0 else {
            return nil
        }
        return seconds
    }
#endif

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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
