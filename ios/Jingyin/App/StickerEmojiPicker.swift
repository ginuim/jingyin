import SwiftUI

struct StickerEmojiPicker: View {
    let title: String
    @Binding var selection: StickerEmoji

    private let pageSize = 16

    private var pages: [[StickerEmoji]] {
        let emojis = StickerEmoji.allCases
        return stride(from: 0, to: emojis.count, by: pageSize).map { start in
            Array(emojis[start..<min(start + pageSize, emojis.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TabView {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, emojis in
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 8
                    ) {
                        ForEach(emojis) { emoji in
                            Button {
                                selection = emoji
                            } label: {
                                Text(emoji.rawValue)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        selection == emoji
                                            ? Color.mint.opacity(0.9)
                                            : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji.rawValue)
                            .accessibilityAddTraits(
                                selection == emoji ? .isSelected : []
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 224)
        }
    }
}
