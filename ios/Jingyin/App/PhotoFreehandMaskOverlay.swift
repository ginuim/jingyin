import SwiftUI

struct PhotoFreehandMaskOverlay: View {
    let groups: [PhotoMaskGroup]
    @Binding var selectedTrackID: MaskTrack.ID?
    @Binding var isDrawing: Bool
    let displaySize: CGSize?
    let brushWidth: Double
    let onComplete: (NormalizedMaskPath) -> Void
    let onDelete: (MaskTrack.ID) -> Void
    var accentColor: Color = AppPalette.accent.primary

    @EnvironmentObject private var localization: LocalizationManager
    @State private var draftPoints: [NormalizedMaskPath.Point] = []

    var body: some View {
        GeometryReader { proxy in
            let imageBounds = VideoCoordinateSpace.aspectFitBounds(
                displaySize: displaySize,
                in: proxy.size
            )
            ZStack {
                ForEach(groups.filter(\.hasManualPath)) { group in
                    if let normalizedPath = group.manualPath {
                        let isSelected = selectedTrackID == group.id
                        let lineWidth = CGFloat(normalizedPath.strokeWidth)
                            * min(imageBounds.width, imageBounds.height)
                        // Keep an invisible, finger-sized hit target so the
                        // rendered privacy effect remains selectable without
                        // drawing the stored brush trajectory over the photo.
                        freehandShape(normalizedPath, in: imageBounds)
                            .stroke(
                                Color.black.opacity(0.001),
                                style: StrokeStyle(
                                    lineWidth: max(lineWidth, 44),
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .onTapGesture {
                                guard !isDrawing else { return }
                                selectedTrackID = group.id
                            }

                        if isSelected && !isDrawing {
                            let rect = normalizedPath.boundingRect
                                .rect(inPreviewBounds: imageBounds)
                            Button {
                                onDelete(group.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(AppPalette.maskOutline)
                                    .frame(width: 28, height: 28)
                                    .background(AppPalette.destructive, in: Circle())
                                    .overlay {
                                        Circle().stroke(AppPalette.maskOutline, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: min(max(rect.maxX, imageBounds.minX + 14), imageBounds.maxX - 14),
                                y: min(max(rect.minY, imageBounds.minY + 14), imageBounds.maxY - 14)
                            )
                            .accessibilityLabel(localization.t("editor.deleteEntireMask"))
                        }
                    }
                }

                if isDrawing {
                    if draftPoints.count >= 2 {
                        freehandShape(draftPoints, in: imageBounds)
                            .stroke(
                                accentColor.opacity(0.64),
                                style: StrokeStyle(
                                    lineWidth: CGFloat(brushWidth)
                                        * min(imageBounds.width, imageBounds.height),
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawingGesture(in: imageBounds))
                }
            }
        }
        .clipped()
        .onChange(of: isDrawing) { _, drawing in
            if !drawing {
                draftPoints = []
            }
        }
    }

    private func freehandShape(
        _ path: NormalizedMaskPath,
        in bounds: CGRect
    ) -> Path {
        freehandShape(path.points, in: bounds)
    }

    private func freehandShape(
        _ points: [NormalizedMaskPath.Point],
        in bounds: CGRect
    ) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let target = CGPoint(
                    x: bounds.minX + CGFloat(point.x) * bounds.width,
                    y: bounds.minY + CGFloat(point.y) * bounds.height
                )
                if index == 0 {
                    path.move(to: target)
                } else {
                    path.addLine(to: target)
                }
            }
            if points.count == 1, let point = points.first {
                path.addLine(to: CGPoint(
                    x: bounds.minX + CGFloat(point.x) * bounds.width + 0.01,
                    y: bounds.minY + CGFloat(point.y) * bounds.height
                ))
            }
        }
    }

    private func drawingGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard bounds.width > 0, bounds.height > 0,
                      bounds.contains(value.location) else { return }
                let point = NormalizedMaskPath.Point(
                    x: Double((value.location.x - bounds.minX) / bounds.width),
                    y: Double((value.location.y - bounds.minY) / bounds.height)
                )
                if let previous = draftPoints.last {
                    let distance = hypot(point.x - previous.x, point.y - previous.y)
                    guard distance >= 0.002 else { return }
                }
                draftPoints.append(point)
            }
            .onEnded { _ in
                defer {
                    draftPoints = []
                    isDrawing = false
                }
                guard let path = NormalizedMaskPath(
                    points: draftPoints,
                    strokeWidth: brushWidth
                ) else { return }
                onComplete(path)
            }
    }
}
