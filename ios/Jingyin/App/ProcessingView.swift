import AVKit
import Photos
import SwiftUI

struct ProcessingView: View {
    let videoURL: URL
    let options: ProcessingOptions
    @StateObject private var processor = VideoProcessor()
    @State private var showShare = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            stageIcon
            VStack(spacing: 10) {
                Text(processor.stage.title)
                    .font(.title2.bold())
                Text("\(Int(processor.progress * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: processor.progress)
                    .tint(.mint)
                if let advisory = processor.advisory {
                    Label(advisory, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            if case let .failed(message) = processor.stage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("重试") { start() }
                    .buttonStyle(.borderedProminent)
            }

            if let output = processor.outputURL {
                VideoPlayer(player: AVPlayer(url: output))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)

                HStack {
                    Button {
                        Task { saved = await processor.saveToPhotos() }
                    } label: {
                        Label(saved ? "已保存" : "保存到相册", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showShare = true
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
            if processor.isRunning {
                Button("取消处理", role: .destructive) {
                    processor.cancel()
                }
            }
        }
        .padding()
        .background(Color(red: 0.035, green: 0.065, blue: 0.07))
        .navigationTitle("处理")
        .navigationBarBackButtonHidden(processor.isRunning)
        .task { start() }
        .sheet(isPresented: $showShare) {
            if let output = processor.outputURL {
                ShareSheet(items: [output])
            }
        }
    }

    private var stageIcon: some View {
        Image(systemName: processor.outputURL == nil ? "gearshape.2.fill" : "checkmark.shield.fill")
            .font(.system(size: 56))
            .foregroundStyle(.mint)
            .symbolEffect(.pulse, options: .repeating, isActive: processor.isRunning)
    }

    private func start() {
        Task { await processor.process(sourceURL: videoURL, options: options) }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
