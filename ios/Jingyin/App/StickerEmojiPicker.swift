import SwiftUI

struct StickerEmojiPicker: View {
    @Binding var selection: StickerEmoji
    var accentColor: Color = .mint
    @State private var selectedPage = 0

    private let pageSize = 8

    private var pages: [[StickerEmoji]] {
        let emojis = StickerEmoji.allCases
        return stride(from: 0, to: emojis.count, by: pageSize).map { start in
            Array(emojis[start..<min(start + pageSize, emojis.count)])
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $selectedPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, emojis in
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 6
                    ) {
                        ForEach(emojis) { emoji in
                            Button {
                                selection = emoji
                            } label: {
                                Text(emoji.rawValue)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(
                                        selection == emoji
                                            ? accentColor.opacity(0.9)
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
                    .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 78)

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { pageIndex in
                    Circle()
                        .fill(
                            pageIndex == selectedPage
                                ? Color.white
                                : Color.white.opacity(0.35)
                        )
                        .frame(width: 7, height: 7)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
    }
}
