import SwiftUI

struct MaskEditorOverlay: View {
    @Binding var tracks: [MaskTrack]
    @Binding var selectedTrackID: MaskTrack.ID?
    let timeSeconds: TimeInterval
    let videoDisplaySize: CGSize?
    let onEditingBegan: () -> Void
    let onEditingEnded: () -> Void
    let onDeleteTrack: (MaskTrack.ID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let videoBounds = VideoCoordinateSpace.aspectFitBounds(
                displaySize: videoDisplaySize,
                in: proxy.size
            )
            ZStack {
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
                            }
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
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.red, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.85), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Circle().inset(by: -6))
                .position(
                    x: min(max(previewRect.maxX, videoBounds.minX + 14), videoBounds.maxX - 14),
                    y: min(max(previewRect.minY, videoBounds.minY + 14), videoBounds.maxY - 14)
                )
                .accessibilityLabel(localization.t("editor.deleteEntireMask"))

                Circle()
                    .fill(.mint)
                    .stroke(.black.opacity(0.8), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle().inset(by: -8))
                    .position(x: previewRect.maxX, y: previewRect.maxY)
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
                .fill(.mint.opacity(isSelected ? 0.16 : 0.08))
                .stroke(
                    isSelected ? .mint : .white.opacity(0.8),
                    style: StrokeStyle(
                        lineWidth: isSelected ? 3 : 2,
                        dash: isSelected ? [] : [6, 5]
                    )
                )
        case .rectangle:
            Rectangle()
                .fill(.mint.opacity(isSelected ? 0.16 : 0.08))
                .stroke(
                    isSelected ? .mint : .white.opacity(0.8),
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
        updated.setKeyframe(
            MaskKeyframe(timeSeconds: timeSeconds, rect: rect)
        )
        track = updated
    }
}
