import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var pickedItem: PhotosPickerItem?
    @State private var importedURL: URL?
    @State private var ownedInputURL: URL?
    @State private var showFileImporter = false
    @State private var loadingImport = false
    @State private var showSettings = false
    @State private var hasCleanedTemporaryFiles = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.08, blue: 0.09), Color(red: 0.06, green: 0.15, blue: 0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer()
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 58, weight: .semibold))
                        .foregroundStyle(.mint)
                        .padding(24)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))

                    VStack(spacing: 8) {
                        Text(localization.t("brand.name"))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(localization.t("home.tagline"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 28)
                    }

                    VStack(spacing: 12) {
                        PhotosPicker(selection: $pickedItem, matching: .videos) {
                            Label(localization.t("home.pickPhotos"), systemImage: "photo.on.rectangle.angled")
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            showFileImporter = true
                        } label: {
                            Label(localization.t("home.pickFiles"), systemImage: "folder")
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, 28)

                    Label(localization.t("home.privacy"), systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                    Spacer()
                }
                .foregroundStyle(.white)

                if loadingImport {
                    ProgressView(localization.t("home.reading"))
                        .padding(22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(localization.t("settings.title"))
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $importedURL) { url in
                EditorView(videoURL: url)
            }
            .task {
                cleanupTemporaryFilesOnce()
                await loadDemoVideoIfRequested()
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
    private func cleanupTemporaryFilesOnce() {
        guard !hasCleanedTemporaryFiles else { return }
        hasCleanedTemporaryFiles = true
        let directory = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in urls where url.lastPathComponent.hasPrefix("jingyin-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Debug helper: `simctl launch … -demoVideo /path/to.mp4`
    @MainActor
    private func loadDemoVideoIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demoVideo"),
              args.indices.contains(index + 1) else { return }
        let source = URL(fileURLWithPath: args[index + 1])
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        await importFile(source)
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        loadingImport = true
        defer {
            loadingImport = false
            pickedItem = nil
        }
        guard let video = try? await item.loadTransferable(type: ImportedVideo.self) else {
            return
        }
        replaceImportedVideo(with: video.url)
    }

    @MainActor
    private func importFile(_ source: URL) async {
        loadingImport = true
        defer { loadingImport = false }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let destination = try ImportedVideo.copyToTemporaryDirectory(source)
            replaceImportedVideo(with: destination)
        } catch {
            return
        }
    }

    @MainActor
    private func replaceImportedVideo(with url: URL) {
        if let ownedInputURL, ownedInputURL != url {
            try? FileManager.default.removeItem(at: ownedInputURL)
        }
        ownedInputURL = url
        importedURL = url
    }
}

private struct ImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            Self(url: try copyToTemporaryDirectory(received.file))
        }
    }

    static func copyToTemporaryDirectory(_ source: URL) throws -> URL {
        let pathExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-input-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
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
