import SwiftUI

struct StickerEmojiPicker: View {
    let title: String
    @Binding var selection: StickerEmoji

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: 8
            ) {
                ForEach(StickerEmoji.allCases) { emoji in
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
                    .accessibilityAddTraits(selection == emoji ? .isSelected : [])
                }
            }
        }
    }
}
