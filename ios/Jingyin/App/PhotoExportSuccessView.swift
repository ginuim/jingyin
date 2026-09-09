import SwiftUI
import UIKit

struct PhotoExportResult: Identifiable, Hashable {
    let id: UUID
    let outputURLs: [URL]
    let totalDraftCount: Int
    let limitedToCurrentPhoto: Bool

    var successCount: Int { outputURLs.count }
    var remainingCount: Int { max(totalDraftCount - successCount, 0) }

    init(
        outputURLs: [URL],
        totalDraftCount: Int,
        limitedToCurrentPhoto: Bool
    ) {
        self.id = UUID()
        self.outputURLs = outputURLs
        self.totalDraftCount = totalDraftCount
        self.limitedToCurrentPhoto = limitedToCurrentPhoto
    }
}

struct PhotoExportSuccessView: View {
    let result: PhotoExportResult
    let onReturnHome: () -> Void

    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore

    @State private var saved = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var showSaveToast = false
    @State private var saveToastTask: Task<Void, Never>?
    @State private var showShare = false
    @State private var showPaywall = false
    @State private var playConfetti = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.surface, AppPalette.background],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    ExportInspectionPreview(urls: result.outputURLs)
                        .frame(height: 330)
                        .padding(.horizontal, 20)
                    successSummary
                    primaryActions
                    secondaryActions
                }
                .padding(.top, 18)
                .padding(.bottom, 36)
            }

            if playConfetti {
                ConfettiBurstView {
                    playConfetti = false
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }

            if showSaveToast {
                VStack {
                    Spacer()
                    Label(
                        localization.format("photo.savedCount", Int64(result.successCount)),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(AppPalette.success, lineWidth: 1)
                    }
                    .foregroundStyle(AppPalette.primaryText)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }
        }
        .foregroundStyle(AppPalette.primaryText)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showSaveToast)
        .navigationTitle(localization.t("photo.processingComplete"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: result.outputURLs)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(localization)
                .environmentObject(entitlements)
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
            if let saveErrorMessage {
                Text(saveErrorMessage)
            }
        }
        .onDisappear {
            saveToastTask?.cancel()
            PhotoProcessor.removeOutputs(at: result.outputURLs)
        }
    }

    private var successSummary: some View {
        VStack(spacing: 9) {
            Text(processedCountText)
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)

            Text(localization.t("photo.metadataCleared"))
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if result.limitedToCurrentPhoto && result.remainingCount > 0 {
                Text(localization.format(
                    "photo.resultRemaining",
                    Int64(result.remainingCount)
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.accent.primary)
                .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
    }

    private var primaryActions: some View {
        VStack(spacing: 14) {
            Button {
                saveOutputs()
            } label: {
                ZStack {
                    Text(
                        saved
                            ? localization.t("processing.savedAndViewPhotos")
                            : localization.t("photo.save")
                    )
                    .opacity(isSaving ? 0 : 1)

                    if isSaving {
                        ProgressView()
                            .tint(AppPalette.accent.foreground)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving || result.outputURLs.isEmpty)

            Button {
                showShare = true
            } label: {
                Text(localization.t("processing.share"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(result.outputURLs.isEmpty)
        }
        .padding(.horizontal, 28)
    }

    private var secondaryActions: some View {
        VStack(spacing: 4) {
            textButton(localization.t("photo.returnHome")) {
                onReturnHome()
            }
            if !entitlements.isUnlocked {
                outlinedButton(localization.t("photo.unlockBatchExport")) {
                    showPaywall = true
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
    }

    private var processedCountText: String {
        if result.successCount == 1 {
            localization.t("photo.processedSingle")
        } else {
            localization.format("photo.processedCount", Int64(result.successCount))
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(TextButtonStyle())
    }

    private func outlinedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.primaryText)
        .overlay {
            Capsule().stroke(AppPalette.primaryText, lineWidth: 1)
        }
    }

    private func saveOutputs() {
        guard !result.outputURLs.isEmpty, !isSaving else { return }
        if saved {
            PhotoLibraryNavigator.openPhotos()
            return
        }
        isSaving = true
        saveErrorMessage = nil
        Task {
            do {
                try await PhotoProcessor.saveToPhotos(result.outputURLs)
                saved = true
                presentSaveToast()
            } catch PhotoProcessor.ProcessingError.photoAccessDenied {
                saveErrorMessage = localization.t("photo.saveAccessDenied")
            } catch {
                saveErrorMessage = localization.t("photo.saveFailedDetail")
            }
            isSaving = false
        }
    }

    private func presentSaveToast() {
        saveToastTask?.cancel()
        showSaveToast = true
        saveToastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            showSaveToast = false
        }
    }
}

private struct ExportInspectionPreview: View {
    let urls: [URL]

    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 10) {
            if urls.indices.contains(selectedIndex) {
                ZoomableExportPreview(url: urls[selectedIndex])
                    .id(urls[selectedIndex])
            } else {
                ProgressView()
            }

            HStack(spacing: 18) {
                Button {
                    selectedIndex = max(selectedIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(selectedIndex == 0)

                Text(localization.format(
                    "photo.exportProgress",
                    Int64(selectedIndex + 1),
                    Int64(urls.count)
                ))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 64)

                Button {
                    selectedIndex = min(selectedIndex + 1, urls.count - 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(selectedIndex >= urls.count - 1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ZoomableExportPreview: View {
    let url: URL

    @State private var thumbnail: UIImage?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let previewSize = fittedPreviewSize(in: proxy.size)
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .frame(width: previewSize.width, height: previewSize.height)
                        .scaleEffect(displayScale)
                        .offset(displayOffset)
                        .gesture(zoomGesture.simultaneously(with: panGesture))
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scale = 1
                                offset = .zero
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(0.16), radius: 7, y: 3)
                } else {
                    ProgressView()
                        .tint(AppPalette.secondaryText)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Leave enough breathing room for the drop shadow, including below
        // the image. The previous 6pt inset clipped the lower blur edge.
        .padding(10)
        .clipped()
        .task(id: url) {
            guard let source = UIImage(contentsOfFile: url.path) else { return }
            thumbnail = await source.byPreparingThumbnail(
                ofSize: CGSize(width: 1_600, height: 1_600)
            ) ?? source
        }
    }

    private var displayScale: CGFloat {
        min(max(scale * gestureScale, 1), 4)
    }

    private func fittedPreviewSize(in container: CGSize) -> CGSize {
        guard let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 else {
            return container
        }
        let scale = min(
            container.width / thumbnail.size.width,
            container.height / thumbnail.size.height
        )
        return CGSize(
            width: thumbnail.size.width * scale,
            height: thumbnail.size.height * scale
        )
    }

    private var displayOffset: CGSize {
        guard displayScale > 1 else { return .zero }
        return CGSize(
            width: offset.width + gestureOffset.width,
            height: offset.height + gestureOffset.height
        )
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                scale = min(max(scale * value, 1), 4)
                if scale == 1 { offset = .zero }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                guard displayScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard displayScale > 1 else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }
}

/// Opens the system Photos app after a successful save. Photos does not offer a
/// deep link to the individual asset that was just created.
@MainActor
enum PhotoLibraryNavigator {
    static func openPhotos() {
        guard let photosURL = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(photosURL)
    }
}

/// One-shot confetti burst. Starts after onAppear so the page can settle first,
/// then explodes from the success icon area instead of already falling.
struct ConfettiBurstView: View {
    var onFinished: () -> Void = {}

    private struct Piece {
        let angle: Double
        let speed: CGFloat
        let spin: Double
        let width: CGFloat
        let height: CGFloat
        let color: Color
        let delayJitter: Double
    }

    /// Hold still so the success UI is readable, then burst.
    private let holdBeforeBurst: Double = 0.32
    private let burstDuration: Double = 1.85
    private let gravity: CGFloat = 1.55
    private let originX: CGFloat = 0.5
    private let originY: CGFloat = 0.22

    @State private var startedAt: Date?
    @State private var didFinish = false

    private let pieces: [Piece] = {
        let colors: [Color] = [
            Color(red: 0.35, green: 0.95, blue: 0.75),
            Color(red: 0.25, green: 0.85, blue: 1.0),
            Color(red: 1.0, green: 0.85, blue: 0.2),
            Color(red: 1.0, green: 0.45, blue: 0.7),
            Color(red: 1.0, green: 0.55, blue: 0.2),
            Color(red: 0.7, green: 0.5, blue: 1.0),
            .white,
        ]
        var rng = SeededGenerator(seed: 20260806)
        return (0..<72).map { index in
            let baseAngle = (Double(index) / 72.0) * .pi * 2
            let wobble = Double.random(in: -0.35...0.35, using: &rng)
            return Piece(
                angle: baseAngle + wobble,
                speed: CGFloat.random(in: 0.55...1.15, using: &rng),
                spin: Double.random(in: -720...720, using: &rng),
                width: CGFloat.random(in: 8...14, using: &rng),
                height: CGFloat.random(in: 12...22, using: &rng),
                color: colors.randomElement(using: &rng) ?? AppPalette.accent.primary,
                delayJitter: Double.random(in: 0...0.08, using: &rng)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: startedAt == nil)) { context in
            Canvas { canvas, size in
                guard let startedAt else { return }
                let elapsed = context.date.timeIntervalSince(startedAt)
                let total = holdBeforeBurst + burstDuration
                guard elapsed < total else { return }

                for piece in pieces {
                    let local = elapsed - holdBeforeBurst - piece.delayJitter
                    guard local > 0 else { continue }

                    let vx = CGFloat(cos(piece.angle)) * piece.speed
                    // Negative vy = shoot upward first, then gravity pulls down.
                    let vy0 = CGFloat(sin(piece.angle)) * piece.speed * 0.55 - piece.speed * 0.85
                    let x = (originX + vx * local) * size.width
                    let y = (originY + vy0 * local + 0.5 * gravity * local * local) * size.height

                    let pop = min(1, local / 0.08)
                    let fadeStart = burstDuration - 0.55
                    let fade = local < fadeStart
                        ? 1.0
                        : max(0, 1 - (local - fadeStart) / 0.55)

                    let transform = CGAffineTransform.identity
                        .translatedBy(x: x, y: y)
                        .rotated(by: Angle.degrees(piece.spin * local).radians)
                        .scaledBy(x: pop, y: pop)
                    let rect = CGRect(
                        x: -piece.width / 2,
                        y: -piece.height / 2,
                        width: piece.width,
                        height: piece.height
                    )
                    canvas.opacity = fade
                    canvas.fill(
                        Path(roundedRect: rect, cornerRadius: 2).applying(transform),
                        with: .color(piece.color)
                    )
                }
            }
        }
        .onAppear {
            guard startedAt == nil else { return }
            startedAt = Date()
            let lifetime = holdBeforeBurst + burstDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
                guard !didFinish else { return }
                didFinish = true
                onFinished()
            }
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
