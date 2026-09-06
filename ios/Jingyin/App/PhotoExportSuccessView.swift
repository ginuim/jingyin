import SwiftUI
import UIKit

struct PhotoExportResult: Identifiable, Hashable {
    let id: UUID
    let outputURLs: [URL]

    var successCount: Int { outputURLs.count }

    init(outputURLs: [URL]) {
        self.id = UUID()
        self.outputURLs = outputURLs
    }
}

struct PhotoExportSuccessView: View {
    let result: PhotoExportResult
    let onReturnHome: () -> Void

    @Environment(\.dismiss) private var dismiss
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
                VStack(spacing: 24) {
                    StackedExportPreview(urls: result.outputURLs)
                        .frame(height: 310)
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
                            ? localization.t("processing.saved")
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
            .buttonStyle(.plain)
            .background(
                AppPalette.accent.primary,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .foregroundStyle(AppPalette.accent.foreground)
            .disabled(saved || isSaving || result.outputURLs.isEmpty)

            Button {
                showShare = true
            } label: {
                Text(localization.t("processing.share"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.primaryText)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppPalette.primaryText, lineWidth: 1.25)
            }
            .disabled(result.outputURLs.isEmpty)
        }
        .padding(.horizontal, 28)
    }

    private var secondaryActions: some View {
        VStack(spacing: 4) {
            textButton(localization.t("photo.continueReview")) {
                dismiss()
            }
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
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.secondaryText)
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

private struct StackedExportPreview: View {
    let urls: [URL]

    private var previewURLs: [URL] {
        Array(urls.prefix(3))
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.62, 230)
            let cardHeight = min(geo.size.height * 0.78, cardWidth * 1.18)
            ZStack {
                ForEach(Array(previewURLs.enumerated()), id: \.offset) { index, url in
                    let placement = placement(for: index, count: previewURLs.count)
                    ExportPreviewCard(
                        url: url,
                        width: cardWidth,
                        height: cardHeight
                    )
                    .rotationEffect(.degrees(placement.rotation))
                    .offset(x: placement.x, y: placement.y)
                    .zIndex(placement.zIndex)
                }

                if urls.count > previewURLs.count {
                    Text("+\(urls.count - previewURLs.count)")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(AppPalette.primaryText)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().stroke(AppPalette.divider, lineWidth: 1)
                        }
                        .offset(x: cardWidth * 0.52, y: -cardHeight * 0.43)
                        .zIndex(5)
                        .accessibilityLabel(
                            localization.format(
                                "photo.morePhotos",
                                Int64(urls.count - previewURLs.count)
                            )
                        )
                }

                successSeal
                    .offset(x: cardWidth * 0.49, y: cardHeight * 0.44)
                    .zIndex(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    @EnvironmentObject private var localization: LocalizationManager

    private var successSeal: some View {
        ZStack {
            Circle()
                .fill(AppPalette.success)
            Circle()
                .stroke(.white.opacity(0.88), lineWidth: 2)
                .padding(6)
            Image(systemName: "checkmark")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    private func placement(for index: Int, count: Int) -> CardPlacement {
        switch count {
        case 1:
            CardPlacement(x: 0, y: 0, rotation: 0, zIndex: 1)
        case 2:
            index == 0
                ? CardPlacement(x: -38, y: -14, rotation: -7, zIndex: 0)
                : CardPlacement(x: 38, y: 18, rotation: 7, zIndex: 1)
        default:
            switch index {
            case 0:
                CardPlacement(x: -46, y: -28, rotation: -7, zIndex: 1)
            case 1:
                CardPlacement(x: 48, y: -6, rotation: 8, zIndex: 0)
            default:
                CardPlacement(x: -6, y: 38, rotation: -4, zIndex: 2)
            }
        }
    }

    private struct CardPlacement {
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
        let zIndex: Double
    }
}

private struct ExportPreviewCard: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                AppPalette.elevatedSurface
                    .overlay {
                        ProgressView()
                            .tint(AppPalette.secondaryText)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.26), radius: 8, y: 4)
        .task(id: url) {
            guard let source = UIImage(contentsOfFile: url.path) else { return }
            thumbnail = await source.byPreparingThumbnail(
                ofSize: CGSize(width: 900, height: 1_080)
            ) ?? source
        }
    }
}

/// One-shot confetti burst. Starts after onAppear so the page can settle first,
/// then explodes from the success icon area instead of already falling.
private struct ConfettiBurstView: View {
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
