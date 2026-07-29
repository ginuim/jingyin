import AVFoundation
import AVKit
import SwiftUI

struct FullScreenMaskEditorView: View {
    let player: AVPlayer
    @Binding var tracks: [MaskTrack]
    @Binding var selectedTrackID: MaskTrack.ID?
    @Binding var playheadSeconds: TimeInterval
    let videoDisplaySize: CGSize?
    let timelineMarkers: [VideoTimelineMarker]
    let timelineRanges: [VideoTimelineRange]
    let canDeleteCurrentKeyframe: Bool
    let onAddMask: (MaskTrackShape) -> Void
    let onInsertKeyframe: () -> Void
    let onDeleteCurrentKeyframe: () -> Void
    let onSetStart: () -> Void
    let onSetEnd: () -> Void
    let onShowWholeTimeline: () -> Void
    let onDeleteTrack: (MaskTrack.ID) -> Void
    let onEditingEnded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ControlledVideoPlayer(
                    player: player,
                    showsCentralPlayButton: selectedTrackID == nil,
                    timelineMarkers: timelineMarkers,
                    timelineRanges: timelineRanges,
                    onTimeChanged: { playheadSeconds = $0 }
                ) {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .overlay {
                            MaskEditorOverlay(
                                tracks: $tracks,
                                selectedTrackID: $selectedTrackID,
                                timeSeconds: playheadSeconds,
                                videoDisplaySize: videoDisplaySize,
                                onEditingBegan: {
                                    player.pause()
                                },
                                onEditingEnded: onEditingEnded,
                                onDeleteTrack: onDeleteTrack
                            )
                        }
                }
                .frame(maxHeight: .infinity)

                maskSelector
                editingControls
            }
            .padding(.horizontal)
            .padding(.bottom)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localization.t("editor.fullScreenTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.t("editor.done")) {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            player.pause()
        }
    }

    private var videoAspectRatio: CGFloat {
        guard let videoDisplaySize,
              videoDisplaySize.width > 0,
              videoDisplaySize.height > 0 else {
            return 16 / 9
        }
        return videoDisplaySize.width / videoDisplaySize.height
    }

    private var maskSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.pause()
                        selectedTrackID = track.id
                    } label: {
                        Label(
                            localization.format("editor.maskItem", Int64(index + 1)),
                            systemImage: track.shape == .ellipse
                                ? "circle.dashed"
                                : "rectangle.dashed"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            selectedTrackID == track.id
                                ? Color.mint
                                : Color.white.opacity(0.1),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedTrackID == track.id ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onAddMask(.ellipse)
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(localization.t("editor.addEllipse"))

                Button {
                    onAddMask(.rectangle)
                } label: {
                    Image(systemName: "plus.rectangle")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(localization.t("editor.addRectangle"))
            }
        }
    }

    private var editingControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                controlButton(
                    title: localization.t("editor.insertKeyframe"),
                    systemImage: "diamond.fill",
                    action: onInsertKeyframe
                )
                controlButton(
                    title: localization.t("editor.deleteKeyframe"),
                    systemImage: "diamond.slash",
                    role: .destructive,
                    isDisabled: !canDeleteCurrentKeyframe,
                    action: onDeleteCurrentKeyframe
                )
                controlButton(
                    title: localization.t("editor.setMaskStart"),
                    systemImage: "inset.filled.leadinghalf.rectangle",
                    action: onSetStart
                )
                controlButton(
                    title: localization.t("editor.setMaskEnd"),
                    systemImage: "inset.filled.trailinghalf.rectangle",
                    action: onSetEnd
                )
                controlButton(
                    title: localization.t("editor.showWholeTimeline"),
                    systemImage: "arrow.left.and.right",
                    action: onShowWholeTimeline
                )
            }
        }
        .disabled(selectedTrackID == nil)
    }

    private func controlButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
}
