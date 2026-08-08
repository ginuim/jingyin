import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit

struct VideoTimelineMarker: Equatable, Identifiable {
    let id: UUID
    let timeSeconds: TimeInterval
    let isSelected: Bool
}

struct VideoTimelineRange: Equatable, Identifiable {
    let id: UUID
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval?
    let isSelected: Bool
}

/// Renders `AVPlayer` frames without AVKit's built-in transport chrome.
/// Custom play/scrub UI lives in `ControlledVideoPlayer` instead.
struct BareVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}

/// Adds an always-visible transport bar without replacing the AVPlayer or its
/// current item. Keeping the same item is important because the live privacy
/// preview is attached through `AVPlayerItem.videoComposition`.
struct ControlledVideoPlayer<Content: View>: View {
    let player: AVPlayer
    let showsCentralPlayButton: Bool
    let timelineMarkers: [VideoTimelineMarker]
    let timelineRanges: [VideoTimelineRange]
    let onTimeChanged: (TimeInterval) -> Void
    let onFullScreen: (() -> Void)?
    let isPinned: Bool
    let onPinToggle: (() -> Void)?
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
        showsCentralPlayButton: Bool = false,
        timelineMarkers: [VideoTimelineMarker] = [],
        timelineRanges: [VideoTimelineRange] = [],
        onTimeChanged: @escaping (TimeInterval) -> Void = { _ in },
        onFullScreen: (() -> Void)? = nil,
        isPinned: Bool = false,
        onPinToggle: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.player = player
        self.showsCentralPlayButton = showsCentralPlayButton
        self.timelineMarkers = timelineMarkers
        self.timelineRanges = timelineRanges
        self.onTimeChanged = onTimeChanged
        self.onFullScreen = onFullScreen
        self.isPinned = isPinned
        self.onPinToggle = onPinToggle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            content
                .overlay(alignment: .topTrailing) {
                    if let onPinToggle {
                        Button(action: onPinToggle) {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isPinned ? AppPalette.accent.foreground : AppPalette.maskOutline)
                                .frame(width: 36, height: 36)
                                .background(
                                    isPinned
                                        ? AppPalette.accent.primary
                                        : AppPalette.mediaScrim,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            localization.t(
                                isPinned ? "player.unpin" : "player.pin"
                            )
                        )
                        .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let onFullScreen {
                        Button(action: onFullScreen) {
                            Image(
                                systemName: "arrow.up.left.and.arrow.down.right"
                            )
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppPalette.maskOutline)
                            .frame(width: 36, height: 36)
                            .background(AppPalette.mediaScrim, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(localization.t("player.fullScreen"))
                        .padding(10)
                    }
                }
                .overlay {
                    if playerIsPaused, showsCentralPlayButton {
                        Button(action: togglePlayback) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(AppPalette.accent.foreground)
                                .frame(width: 58, height: 58)
                                .background(AppPalette.accent.primary, in: Circle())
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
                .foregroundStyle(AppPalette.accent.primary)
                .accessibilityLabel(
                    localization.t(playerIsPaused ? "player.play" : "player.pause")
                )

                Text(formatTime(displayedSeconds))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: timeLabelWidth, alignment: .trailing)

                timelineSlider

                Text(formatTime(durationSeconds))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: timeLabelWidth, alignment: .leading)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppPalette.secondaryText)
            .padding(.horizontal, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
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

    private var timelineSlider: some View {
        Slider(
            value: Binding(
                get: { displayedSeconds },
                set: { scrubSeconds = $0 }
            ),
            in: 0...max(durationSeconds, 0.01),
            onEditingChanged: scrubStateChanged
        )
        .tint(AppPalette.accent.primary)
        .disabled(durationSeconds <= 0)
        .overlay {
            GeometryReader { proxy in
                ZStack {
                    ForEach(visibleTimelineRanges) { range in
                        let startX = markerPosition(
                            for: range.startSeconds,
                            width: proxy.size.width
                        )
                        let endX = markerPosition(
                            for: range.endSeconds ?? durationSeconds,
                            width: proxy.size.width
                        )
                        Capsule()
                            .fill(
                                range.isSelected
                                    ? AppPalette.warning
                                    : AppPalette.secondaryText
                            )
                            .frame(width: max(endX - startX, 3), height: 6)
                            .position(
                                x: startX + max(endX - startX, 3) / 2,
                                y: proxy.size.height / 2
                            )
                    }

                    ForEach(visibleTimelineMarkers) { marker in
                        Capsule()
                            .fill(marker.isSelected ? AppPalette.warning : AppPalette.maskOutline)
                            .frame(
                                width: marker.isSelected ? 4 : 3,
                                height: marker.isSelected ? 18 : 12
                            )
                            .shadow(
                                color: AppPalette.maskOutlineShadow,
                                radius: 1
                            )
                            .position(
                                x: markerPosition(
                                    for: marker.timeSeconds,
                                    width: proxy.size.width
                                ),
                                y: proxy.size.height / 2
                            )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel(localization.t("player.progress"))
        .accessibilityValue(
            "\(formatTime(displayedSeconds)) / \(formatTime(durationSeconds))"
        )
    }

    private var visibleTimelineMarkers: [VideoTimelineMarker] {
        timelineMarkers.filter {
            $0.timeSeconds.isFinite
                && $0.timeSeconds >= 0
                && $0.timeSeconds <= durationSeconds
        }
    }

    private var visibleTimelineRanges: [VideoTimelineRange] {
        timelineRanges.filter {
            $0.startSeconds.isFinite
                && $0.startSeconds >= 0
                && $0.startSeconds <= durationSeconds
                && ($0.endSeconds == nil || $0.endSeconds?.isFinite == true)
        }
    }

    private func markerPosition(
        for timeSeconds: TimeInterval,
        width: CGFloat
    ) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        let progress = min(max(timeSeconds / durationSeconds, 0), 1)
        // Keep edge markers visible instead of clipping half their width.
        return 2 + CGFloat(progress) * max(width - 4, 0)
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
