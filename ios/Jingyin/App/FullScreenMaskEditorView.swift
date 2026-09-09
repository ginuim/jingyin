import AVFoundation
import SwiftUI

/// Full-screen is for checking the processed image; region editing stays in
/// the main workspace so transport and a second editor never compete for space.
struct FullScreenMaskEditorView: View {
    let player: AVPlayer
    @Binding var playheadSeconds: TimeInterval
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ControlledVideoPlayer(
                    player: player,
                    onTimeChanged: { playheadSeconds = $0 }
                ) {
                    BareVideoPlayer(player: player)
                        .frame(height: max(80, geometry.size.height
                            - (dynamicTypeSize.isAccessibilitySize ? 110 : 64)))
                }
                .padding(.horizontal, 12)
            }
            .background(AppPalette.mediaCanvas.ignoresSafeArea())
            .navigationTitle(localization.t("editor.fullScreenTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.t("editor.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
