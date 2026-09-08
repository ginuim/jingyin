import SwiftUI

struct MaskEditorOverlay: View {
    @Binding var tracks: [MaskTrack]
    @Binding var selectedTrackID: MaskTrack.ID?
    let timeSeconds: TimeInterval
    let videoDisplaySize: CGSize?
    let onEditingBegan: () -> Void
    let onEditingEnded: () -> Void
    let onDeleteTrack: (MaskTrack.ID) -> Void
    var accentColor: Color = AppPalette.accent.primary

    var body: some View {
        GeometryReader { proxy in
            let videoBounds = VideoCoordinateSpace.aspectFitBounds(
                displaySize: videoDisplaySize,
                in: proxy.size
            )
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture { selectedTrackID = nil }
                ForEach($tracks) { $track in
                    if let normalizedRect = track.rect(at: timeSeconds) {
                        MaskTrackLayer(
                            track: $track,
                            normalizedRect: normalizedRect,
                            videoBounds: videoBounds,
                            timeSeconds: timeSeconds,
                            isSelected: selectedTrackID == track.id,
                            onSelect: {
                                selectedTrackID = track.id
                                onEditingBegan()
                            },
                            onEditingEnded: onEditingEnded,
                            onDelete: {
                                onDeleteTrack(track.id)
                            },
                            accentColor: accentColor
                        )
                    }
                }
            }
        }
        .clipped()
    }

}

private struct MaskTrackLayer: View {
    @Binding var track: MaskTrack
    let normalizedRect: NormalizedVideoRect
    let videoBounds: CGRect
    let timeSeconds: TimeInterval
    let isSelected: Bool
    let onSelect: () -> Void
    let onEditingEnded: () -> Void
    let onDelete: () -> Void
    let accentColor: Color

    @EnvironmentObject private var localization: LocalizationManager
    @State private var moveStartRect: NormalizedVideoRect?
    @State private var resizeStartRect: NormalizedVideoRect?

    var body: some View {
        let previewRect = normalizedRect.rect(inPreviewBounds: videoBounds)
        ZStack {
            maskShape
                .frame(width: previewRect.width, height: previewRect.height)
                .contentShape(Rectangle())
                .position(x: previewRect.midX, y: previewRect.midY)
                .onTapGesture(perform: onSelect)
                .gesture(moveGesture)

            if isSelected {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.maskOutline)
                    .frame(width: 28, height: 28)
                    .background(accentColor, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .position(
                        x: min(max(previewRect.maxX, videoBounds.minX + 22), videoBounds.maxX - 22),
                        y: min(max(previewRect.maxY, videoBounds.minY + 22), videoBounds.maxY - 22)
                    )
                    .gesture(resizeGesture)
                    .accessibilityLabel(localization.t("editor.resizeMask"))
            }
        }
    }

    @ViewBuilder
    private var maskShape: some View {
        switch track.shape {
        case .ellipse:
            Ellipse()
                .fill(accentColor.opacity(isSelected ? 0.16 : 0.08))
                .stroke(
                    isSelected ? accentColor : AppPalette.maskOutline,
                    style: StrokeStyle(
                        lineWidth: isSelected ? 3 : 2,
                        dash: isSelected ? [] : [6, 5]
                    )
                )
        case .rectangle:
            Rectangle()
                .fill(accentColor.opacity(isSelected ? 0.16 : 0.08))
                .stroke(
                    isSelected ? accentColor : AppPalette.maskOutline,
                    style: StrokeStyle(
                        lineWidth: isSelected ? 3 : 2,
                        dash: isSelected ? [] : [6, 5]
                    )
                )
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if moveStartRect == nil {
                    moveStartRect = normalizedRect
                    onSelect()
                }
                let start = moveStartRect ?? normalizedRect
                let deltaX = Double(value.translation.width / max(videoBounds.width, 1))
                let deltaY = Double(value.translation.height / max(videoBounds.height, 1))
                let x = min(max(start.x + deltaX, 0), 1 - start.width)
                let y = min(max(start.y + deltaY, 0), 1 - start.height)
                updateTrack(
                    rect: NormalizedVideoRect(
                        x: x,
                        y: y,
                        width: start.width,
                        height: start.height
                    )
                )
            }
            .onEnded { _ in
                moveStartRect = nil
                onEditingEnded()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeStartRect == nil {
                    resizeStartRect = normalizedRect
                    onSelect()
                }
                let start = resizeStartRect ?? normalizedRect
                let deltaWidth = Double(value.translation.width / max(videoBounds.width, 1))
                let deltaHeight = Double(value.translation.height / max(videoBounds.height, 1))
                let width = min(max(start.width + deltaWidth, 0.05), 1 - start.x)
                let height = min(max(start.height + deltaHeight, 0.05), 1 - start.y)
                updateTrack(
                    rect: NormalizedVideoRect(
                        x: start.x,
                        y: start.y,
                        width: width,
                        height: height
                    )
                )
            }
            .onEnded { _ in
                resizeStartRect = nil
                onEditingEnded()
            }
    }

    private func updateTrack(rect: NormalizedVideoRect) {
        var updated = track
        updated.updateManualRect(rect, at: timeSeconds)
        track = updated
    }
}
