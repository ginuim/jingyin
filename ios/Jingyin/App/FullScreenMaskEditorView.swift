import AVFoundation
import AVKit
import SwiftUI

struct FullScreenMaskEditorView<Controls: View>: View {
    let player: AVPlayer
    @Binding var tracks: [MaskTrack]
    @Binding var selectedTrackID: MaskTrack.ID?
    @Binding var playheadSeconds: TimeInterval
    let videoDisplaySize: CGSize?
    let timelineMarkers: [VideoTimelineMarker]
    let timelineRanges: [VideoTimelineRange]
    let isMaskEditingEnabled: Bool
    let onEditingBegan: () -> Void
    let onDeleteTrack: (MaskTrack.ID) -> Void
    let onEditingEnded: () -> Void
    @ViewBuilder var controls: Controls

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    ControlledVideoPlayer(
                        player: player,
                        timelineMarkers: timelineMarkers,
                        timelineRanges: timelineRanges,
                        onTimeChanged: { playheadSeconds = $0 }
                    ) {
                        BareVideoPlayer(player: player)
                            .frame(height: max(120, geometry.size.height * 0.45))
                            .overlay {
                                if isMaskEditingEnabled {
                                    MaskEditorOverlay(
                                        tracks: $tracks,
                                        selectedTrackID: $selectedTrackID,
                                        timeSeconds: playheadSeconds,
                                        videoDisplaySize: videoDisplaySize,
                                        onEditingBegan: {
                                            onEditingBegan()
                                        },
                                        onEditingEnded: onEditingEnded,
                                        onDeleteTrack: onDeleteTrack
                                    )
                                }
                            }
                    }
                    .frame(maxHeight: .infinity)

                    if isMaskEditingEnabled {
                        ScrollView { controls.padding(16) }
                            .frame(maxHeight: 280)
                            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .background(AppPalette.mediaCanvas.ignoresSafeArea())
            }
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
    }

    private var videoAspectRatio: CGFloat {
        guard let videoDisplaySize,
              videoDisplaySize.width > 0,
              videoDisplaySize.height > 0 else {
            return 16 / 9
        }
        return videoDisplaySize.width / videoDisplaySize.height
    }

}
