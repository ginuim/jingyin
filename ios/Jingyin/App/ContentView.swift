import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var pickedItem: PhotosPickerItem?
    @State private var importedURL: URL?
    @State private var showFileImporter = false
    @State private var loadingImport = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.08, blue: 0.09), Color(red: 0.06, green: 0.15, blue: 0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 58, weight: .semibold))
                        .foregroundStyle(.mint)
                        .padding(24)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))

                    VStack(spacing: 10) {
                        Text("镜隐")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("视频隐私，只留在你的设备里")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 14) {
                        PhotosPicker(selection: $pickedItem, matching: .videos) {
                            Label("从相册选择视频", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("从文件选择视频", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, 28)

                    Label("原视频、识别数据和结果均不会上传", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .foregroundStyle(.white)

                if loadingImport {
                    ProgressView("正在读取视频…")
                        .padding(22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .navigationDestination(item: $importedURL) { url in
                EditorView(videoURL: url)
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let source = urls.first else { return }
                Task { await importFile(source) }
            }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        loadingImport = true
        defer { loadingImport = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-input-\(UUID().uuidString).mov")
        do {
            try data.write(to: url, options: .atomic)
            importedURL = url
        } catch {
            importedURL = nil
        }
    }

    @MainActor
    private func importFile(_ source: URL) async {
        loadingImport = true
        defer { loadingImport = false }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-input-\(UUID().uuidString).\(source.pathExtension)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            importedURL = destination
        } catch {
            importedURL = nil
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding()
            .background(Color.mint.opacity(configuration.isPressed ? 0.65 : 0.9))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding()
            .background(.white.opacity(configuration.isPressed ? 0.06 : 0.1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
