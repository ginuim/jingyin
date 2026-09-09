import SwiftUI

/// Single-row mask timeline pinned below the player transport. It shares the
/// thumbnail strip's time→x mapping (same 16pt side inset) so keyframe
/// diamonds and the active-range bar line up with the playhead above.
///
/// Only the selected track is interactive: diamonds seek, and the range bar's
/// end handles adjust `activeFromSeconds` / `activeUntilSeconds`. Other tracks
/// render as faint context bars so multiple masks stay visible without each
/// claiming its own row.
struct MaskTimelineTrackView: View {
    let tracks: [MaskTrack]
    let selectedTrackID: MaskTrack.ID?
    let durationSeconds: TimeInterval
    let playheadSeconds: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onRangeEditBegan: (MaskTrack.ID) -> Void
    let onRangeChanged: (MaskTrack.ID, TimeInterval?, TimeInterval?) -> Void
    let onRangeEditEnded: (MaskTrack.ID) -> Void

    @EnvironmentObject private var localization: LocalizationManager

    @State private var isEditingRange = false

    private let sideInset: CGFloat = 16
    private let rowHeight: CGFloat = 40

    var body: some View {
        if durationSeconds > 0 {
            GeometryReader { proxy in
                let trackWidth = max(proxy.size.width - sideInset * 2, 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppPalette.elevatedSurface)
                        .frame(height: 28)
                        .padding(.horizontal, sideInset / 2)

                    contextBars(trackWidth: trackWidth)

                    if let track = selectedTrack {
                        selectedRangeBar(track: track, trackWidth: trackWidth)
                        keyframeDiamonds(track: track, trackWidth: trackWidth)
                    }

                    playheadLine(trackWidth: trackWidth)
                }
                .frame(width: proxy.size.width, height: rowHeight)
                .coordinateSpace(name: "maskTimelineRow")
            }
            .frame(height: rowHeight)
            .accessibilityElement(children: .contain)
        }
    }

    private var selectedTrack: MaskTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    private func xPosition(for time: TimeInterval, trackWidth: CGFloat) -> CGFloat {
        let progress = min(max(time / max(durationSeconds, 0.01), 0), 1)
        return sideInset + CGFloat(progress) * trackWidth
    }

    private func time(atX x: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        let progress = min(max((x - sideInset) / trackWidth, 0), 1)
        return Double(progress) * durationSeconds
    }

    /// Faint, non-interactive presence bars for every unselected track.
    @ViewBuilder
    private func contextBars(trackWidth: CGFloat) -> some View {
        ForEach(tracks.filter { $0.id != selectedTrackID }) { track in
            let startX = xPosition(for: track.activeFromSeconds ?? 0, trackWidth: trackWidth)
            let endX = xPosition(
                for: track.activeUntilSeconds ?? durationSeconds,
                trackWidth: trackWidth
            )
            Capsule()
                .fill(AppPalette.secondaryText.opacity(0.45))
                .frame(width: max(endX - startX, 3), height: 4)
                .position(x: startX + max(endX - startX, 3) / 2, y: rowHeight - 5)
        }
    }

    @ViewBuilder
    private func selectedRangeBar(track: MaskTrack, trackWidth: CGFloat) -> some View {
        let start = track.activeFromSeconds ?? 0
        let end = track.activeUntilSeconds ?? durationSeconds
        let startX = xPosition(for: start, trackWidth: trackWidth)
        let endX = xPosition(for: end, trackWidth: trackWidth)
        let barWidth = max(endX - startX, 4)

        RoundedRectangle(cornerRadius: 5)
            .fill(AppPalette.accent.primary.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(AppPalette.accent.primary, lineWidth: 1)
            )
            .frame(width: barWidth, height: 16)
            .position(x: startX + barWidth / 2, y: rowHeight / 2)
            .accessibilityLabel(localization.t("editor.visibility"))
            .accessibilityValue(selectedRangeSummary(track: track))

        rangeHandle(track: track, isStart: true, trackWidth: trackWidth)
            .position(x: startX, y: rowHeight / 2)
        rangeHandle(track: track, isStart: false, trackWidth: trackWidth)
            .position(x: endX, y: rowHeight / 2)
    }

    private func rangeHandle(
        track: MaskTrack,
        isStart: Bool,
        trackWidth: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(AppPalette.accent.primary)
            .frame(width: 8, height: 20)
            .frame(width: 28, height: rowHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("maskTimelineRow"))
                    .onChanged { value in
                        if !isEditingRange {
                            isEditingRange = true
                            onRangeEditBegan(track.id)
                        }
                        var time = time(atX: value.location.x, trackWidth: trackWidth)
                        if isStart {
                            let end = track.activeUntilSeconds ?? durationSeconds
                            time = min(time, max(end - 0.1, 0))
                            onRangeChanged(track.id, time, track.activeUntilSeconds)
                        } else {
                            let start = track.activeFromSeconds ?? 0
                            time = max(time, min(start + 0.1, durationSeconds))
                            onRangeChanged(track.id, track.activeFromSeconds, time)
                        }
                    }
                    .onEnded { _ in
                        isEditingRange = false
                        onRangeEditEnded(track.id)
                    }
            )
            .accessibilityLabel(
                localization.t(
                    isStart ? "editor.rangeStartHandle" : "editor.rangeEndHandle"
                )
            )
    }

    @ViewBuilder
    private func keyframeDiamonds(track: MaskTrack, trackWidth: CGFloat) -> some View {
        ForEach(track.keyframes.filter { $0.origin == .manual }) { keyframe in
            let isAtPlayhead = abs(keyframe.timeSeconds - playheadSeconds) <= 0.12
            Button {
                onSeek(keyframe.timeSeconds)
            } label: {
                Image(systemName: "diamond.fill")
                    .font(.system(size: isAtPlayhead ? 13 : 10, weight: .bold))
                    .foregroundStyle(
                        isAtPlayhead
                            ? AppPalette.accent.primary
                            : AppPalette.primaryText.opacity(0.75)
                    )
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(
                x: xPosition(for: keyframe.timeSeconds, trackWidth: trackWidth),
                y: rowHeight / 2
            )
            .accessibilityLabel(
                localization.format(
                    "editor.keyframeAt",
                    formatTimestamp(keyframe.timeSeconds)
                )
            )
        }
    }

    private func playheadLine(trackWidth: CGFloat) -> some View {
        Rectangle()
            .fill(AppPalette.accent.primary)
            .frame(width: 2, height: 30)
            .position(
                x: xPosition(for: playheadSeconds, trackWidth: trackWidth),
                y: rowHeight / 2
            )
            .allowsHitTesting(false)
    }

    private func selectedRangeSummary(track: MaskTrack) -> String {
        let start = track.activeFromSeconds.map(formatTimestamp)
            ?? localization.t("editor.showForEntireVideo")
        let end = track.activeUntilSeconds.map(formatTimestamp)
            ?? localization.t("editor.showForEntireVideo")
        return "\(start) – \(end)"
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let total = Int(safeSeconds.rounded(.down))
        return String(
            format: "%d:%04.1f",
            total / 60,
            safeSeconds.truncatingRemainder(dividingBy: 60)
        )
    }
}
