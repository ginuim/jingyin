import SwiftUI
import UIKit

struct FaceSelectionView: View {
    let snapshot: FaceDetectionSnapshot
    let onConfirm: ([DetectedFaceCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedIDs: Set<DetectedFaceCandidate.ID> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                facePreview

                if snapshot.candidates.isEmpty {
                    ContentUnavailableView(
                        localization.t("faceSelection.none"),
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(localization.t("faceSelection.noneHint"))
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(snapshot.candidates.enumerated()), id: \.element.id) {
                                index,
                                candidate in
                                Toggle(
                                    localization.format(
                                        "faceSelection.faceItem",
                                        Int64(index + 1)
                                    ),
                                    isOn: selectionBinding(for: candidate.id)
                                )
                                .toggleStyle(.button)
                                .buttonStyle(.bordered)
                                .tint(AppPalette.accent.primary)
                            }
                        }
                    }
                }

                Text(localization.t("faceSelection.hint"))
                    .font(.footnote)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .foregroundStyle(AppPalette.primaryText)
            .background(AppPalette.background)
            .navigationTitle(localization.t("faceSelection.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.t("faceSelection.trackSelected")) {
                        let selected = snapshot.candidates.filter {
                            selectedIDs.contains($0.id)
                        }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var facePreview: some View {
        GeometryReader { proxy in
            let bounds = VideoCoordinateSpace.aspectFitBounds(
                displaySize: snapshot.displaySize,
                in: proxy.size
            )
            ZStack {
                if let image = UIImage(data: snapshot.previewJPEGData) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                ForEach(Array(snapshot.candidates.enumerated()), id: \.element.id) {
                    index,
                    candidate in
                    let rect = candidate.coverageRect.rect(inPreviewBounds: bounds)
                    Button {
                        toggle(candidate.id)
                    } label: {
                        ZStack(alignment: .topLeading) {
                            Ellipse()
                                .fill(
                                    selectedIDs.contains(candidate.id)
                                        ? AppPalette.accent.softFill
                                        : Color.clear
                                )
                                .stroke(
                                    selectedIDs.contains(candidate.id) ? AppPalette.accent.primary : AppPalette.maskOutline,
                                    style: StrokeStyle(lineWidth: 3, dash: [7, 5])
                                )

                            Label {
                                Text("\(index + 1)")
                            } icon: {
                                Image(
                                    systemName: selectedIDs.contains(candidate.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .font(.caption.bold())
                            .foregroundStyle(
                                selectedIDs.contains(candidate.id) ? AppPalette.accent.foreground : AppPalette.maskOutline
                            )
                            .padding(6)
                            .background(
                                selectedIDs.contains(candidate.id)
                                    ? AppPalette.accent.primary
                                    : AppPalette.mediaScrim,
                                in: Capsule()
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel(
                        localization.format(
                            "faceSelection.faceItem",
                            Int64(index + 1)
                        )
                    )
                    .accessibilityAddTraits(
                        selectedIDs.contains(candidate.id) ? .isSelected : []
                    )
                }
            }
        }
        .aspectRatio(
            max(snapshot.displaySize.width, 1) / max(snapshot.displaySize.height, 1),
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func selectionBinding(
        for id: DetectedFaceCandidate.ID
    ) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }

    private func toggle(_ id: DetectedFaceCandidate.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
