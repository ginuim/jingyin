import SwiftUI
import UIKit

/// Read-only inspection shared by editing and export results. It never transforms
/// mask coordinates: all region editing stays in the unzoomed editor canvas.
struct ZoomablePhotoPreview: View {
    let image: UIImage
    @EnvironmentObject private var localization: LocalizationManager
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let fitted = VideoCoordinateSpace.aspectFitBounds(displaySize: image.size, in: proxy.size).size
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: AppPalette.maskOutlineShadow.opacity(0.18), radius: 7, y: 3)
                    .scaleEffect(displayScale)
                    .offset(clampedOffset(
                        CGSize(width: offset.width + gestureOffset.width,
                               height: offset.height + gestureOffset.height),
                        fitted: fitted, container: proxy.size, scale: displayScale
                    ))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(zoomGesture(fitted: fitted, container: proxy.size)
                        .simultaneously(with: panGesture(fitted: fitted, container: proxy.size)))
                    .onTapGesture(count: 2, perform: reset)
                    .clipped()
                    .accessibilityLabel(localization.t("photo.inspect"))
                    .accessibilityValue("\(Int(displayScale * 100))%")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: scale = min(4, scale + 0.5)
                        case .decrement: scale = max(1, scale - 0.5)
                        @unknown default: break
                        }
                        offset = clampedOffset(offset, fitted: fitted, container: proxy.size, scale: scale)
                    }
            }
            HStack(spacing: 12) {
                Button { scale = max(1, scale - 0.5); offset = .zero } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localization.t("photo.zoomOut"))
                .disabled(scale <= 1)
                Button(action: reset) {
                    Text(localization.t("photo.resetZoom"))
                        .font(.footnote)
                        .frame(minHeight: 44)
                }
                Button { scale = min(4, scale + 0.5) } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localization.t("photo.zoomIn"))
                .disabled(scale >= 4)
            }
            .buttonStyle(.borderless)
        }
    }

    private var displayScale: CGFloat { min(max(scale * gestureScale, 1), 4) }

    private func reset() {
        scale = 1
        offset = .zero
    }

    private func clampedOffset(_ value: CGSize, fitted: CGSize, container: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (fitted.width * scale - container.width) / 2)
        let maxY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX),
                      height: min(max(value.height, -maxY), maxY))
    }

    private func zoomGesture(fitted: CGSize, container: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded { value in
                scale = min(max(scale * value, 1), 4)
                offset = clampedOffset(offset, fitted: fitted, container: container, scale: scale)
            }
    }

    private func panGesture(fitted: CGSize, container: CGSize) -> some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                if displayScale > 1 { state = value.translation }
            }
            .onEnded { value in
                offset = clampedOffset(
                    CGSize(width: offset.width + value.translation.width,
                           height: offset.height + value.translation.height),
                    fitted: fitted, container: container, scale: displayScale)
            }
    }
}
