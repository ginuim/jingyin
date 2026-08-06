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
            Color(red: 0.035, green: 0.065, blue: 0.07)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    successHeader
                    StackedExportPreview(urls: result.outputURLs)
                        .frame(height: 220)
                        .padding(.horizontal, 28)
                    primaryActions
                    secondaryActions
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
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
                        Capsule().stroke(Color.mint.opacity(0.45), lineWidth: 1)
                    }
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showSaveToast)
        .navigationTitle(localization.t("photo.exportSuccess"))
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
        }
    }

    private var successHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.mint)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20)
                )

            Text(localization.t("photo.exportSuccess"))
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(localization.format("photo.exportSuccessDetail", Int64(result.successCount)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                saveOutputs()
            } label: {
                Text(
                    saved
                        ? localization.t("processing.saved")
                        : localization.t("photo.save")
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .background(Color.mint, in: Capsule())
            .foregroundStyle(.black)
            .disabled(isSaving || result.outputURLs.isEmpty)

            Button {
                showShare = true
            } label: {
                Text(localization.t("processing.share"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .overlay {
                Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .disabled(result.outputURLs.isEmpty)
        }
        .padding(.horizontal, 28)
    }

    private var secondaryActions: some View {
        VStack(spacing: 12) {
            outlinedButton(localization.t("photo.continueReview")) {
                dismiss()
            }
            outlinedButton(localization.t("photo.returnHome")) {
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

    private func outlinedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .overlay {
            Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1)
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
            let cardSize = min(geo.size.width * 0.72, geo.size.height * 0.92)
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                ForEach(Array(previewURLs.enumerated().reversed()), id: \.offset) { index, url in
                    let depth = previewURLs.count - 1 - index
                    card(for: url, side: cardSize * 0.78)
                        .rotationEffect(.degrees(depth == 0 ? 0 : (depth % 2 == 0 ? -7 : 7)))
                        .offset(
                            x: depth == 0 ? 0 : (depth % 2 == 0 ? -14 : 14),
                            y: CGFloat(depth) * -6
                        )
                        .opacity(depth == 0 ? 1 : 0.72)
                        .zIndex(Double(index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func card(for url: URL, side: CGFloat) -> some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
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
                color: colors.randomElement(using: &rng) ?? .mint,
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

                    var transform = CGAffineTransform.identity
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
