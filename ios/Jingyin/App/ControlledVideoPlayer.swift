import AVFoundation
import AVKit
import Combine
import SwiftUI

/// Adds an always-visible transport bar without replacing the AVPlayer or its
/// current item. Keeping the same item is important because the live privacy
/// preview is attached through `AVPlayerItem.videoComposition`.
struct ControlledVideoPlayer<Content: View>: View {
    let player: AVPlayer
    let showsCentralPlayButton: Bool
    let onTimeChanged: (TimeInterval) -> Void
    @ViewBuilder private let content: Content

    @EnvironmentObject private var localization: LocalizationManager
    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var scrubSeconds = 0.0
    @State private var isScrubbing = false
    @State private var resumeAfterScrubbing = false
    @State private var playerIsPaused = true

    private let refreshTimer = Timer.publish(
        every: 0.2,
        on: .main,
        in: .common
    ).autoconnect()

    init(
        player: AVPlayer,
        showsCentralPlayButton: Bool = true,
        onTimeChanged: @escaping (TimeInterval) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.player = player
        self.showsCentralPlayButton = showsCentralPlayButton
        self.onTimeChanged = onTimeChanged
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                content

                if playerIsPaused, showsCentralPlayButton {
                    Button(action: togglePlayback) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 58, height: 58)
                            .background(.mint.opacity(0.94), in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.t("player.play"))
                }
            }

            HStack(spacing: 9) {
                Button(action: togglePlayback) {
                    Image(systemName: playerIsPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.mint)
                .accessibilityLabel(
                    localization.t(playerIsPaused ? "player.play" : "player.pause")
                )

                Text(formatTime(displayedSeconds))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: timeLabelWidth, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { displayedSeconds },
                        set: { scrubSeconds = $0 }
                    ),
                    in: 0...max(durationSeconds, 0.01),
                    onEditingChanged: scrubStateChanged
                )
                .tint(.mint)
                .disabled(durationSeconds <= 0)
                .accessibilityLabel(localization.t("player.progress"))
                .accessibilityValue(
                    "\(formatTime(displayedSeconds)) / \(formatTime(durationSeconds))"
                )

                Text(formatTime(durationSeconds))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: timeLabelWidth, alignment: .leading)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .onAppear(perform: refreshState)
        .onReceive(refreshTimer) { _ in
            refreshState()
        }
    }

    private var displayedSeconds: Double {
        isScrubbing ? scrubSeconds : currentSeconds
    }

    private var timeLabelWidth: CGFloat {
        durationSeconds >= 3_600 ? 54 : 38
    }

    private func togglePlayback() {
        if player.timeControlStatus == .paused {
            Task { @MainActor in
                if durationSeconds > 0, currentSeconds >= durationSeconds - 0.05 {
                    await player.seek(
                        to: .zero,
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }
                player.play()
                refreshState()
            }
        } else {
            player.pause()
            refreshState()
        }
    }

    private func scrubStateChanged(_ editing: Bool) {
        if editing {
            isScrubbing = true
            scrubSeconds = currentSeconds
            resumeAfterScrubbing = player.timeControlStatus != .paused
            player.pause()
            refreshState()
            return
        }

        let destination = CMTime(seconds: scrubSeconds, preferredTimescale: 600)
        Task { @MainActor in
            await player.seek(
                to: destination,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            currentSeconds = scrubSeconds
            isScrubbing = false
            if resumeAfterScrubbing {
                player.play()
            }
            resumeAfterScrubbing = false
            refreshState()
        }
    }

    private func refreshState() {
        playerIsPaused = player.timeControlStatus == .paused

        let current = player.currentTime().seconds
        if current.isFinite, !isScrubbing {
            currentSeconds = max(0, current)
            onTimeChanged(currentSeconds)
        }

        let duration = player.currentItem?.duration.seconds ?? 0
        durationSeconds = duration.isFinite && duration > 0 ? duration : 0
        if durationSeconds > 0 {
            currentSeconds = min(currentSeconds, durationSeconds)
            scrubSeconds = min(scrubSeconds, durationSeconds)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let wholeSeconds = Int(seconds.rounded(.down))
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let remainingSeconds = wholeSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
