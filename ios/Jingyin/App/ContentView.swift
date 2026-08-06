import AVKit
import CoreTransferable
import Darwin
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedPhotoItems: [PhotosPickerItem] = []
    @State private var importedURL: URL?
    @State private var importedPhotos: PhotoBatchSelection?
    @State private var ownedInputURL: URL?
    @State private var ownedPhotoURLs: [URL] = []
    @State private var securityScopedInputURL: URL?
    @State private var showFileImporter = false
    @State private var loadingImport = false
    @State private var importFraction: Double?
    @State private var activeImportProgress: Progress?
    @State private var importProgressTask: Task<Void, Never>?
    @State private var photoImportTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var hasCleanedTemporaryFiles = false
    @State private var importErrorKey: String?

    var body: some View {
        NavigationStack {
            landingWithImporters
        }
        .preferredColorScheme(.dark)
    }

    private var landingWithNavigation: some View {
        homeLanding
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
            .navigationDestination(item: $importedPhotos) { selection in
                PhotoBatchEditorView(inputURLs: selection.urls) {
                    importedPhotos = nil
                }
            }
    }

    private var landingWithLifecycle: some View {
        landingWithNavigation
            .onChange(of: importedURL) { _, url in
                if url == nil {
                    releaseImportedVideo()
                }
            }
            .onChange(of: importedPhotos) { _, selection in
                if selection == nil {
                    releaseImportedPhotos()
                }
            }
            .task {
                cleanupTemporaryFilesOnce()
                await loadDemoVideoIfRequested()
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                beginPhotoImport(item)
            }
            .onChange(of: pickedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                beginBatchPhotoImport(items)
            }
    }

    private var landingWithImporters: some View {
        landingWithLifecycle
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let source = urls.first else {
                    return
                }
                Task { await importFile(source) }
            }
            .alert(
                importErrorMessage,
                isPresented: isImportErrorPresented
            ) {
                Button(localization.t("processing.cancel"), role: .cancel) {}
            }
    }

    private var homeLanding: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.09),
                    Color(red: 0.06, green: 0.15, blue: 0.13)
                ],
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

                coverageDisclaimer

                importButtons

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
                importProgressOverlay
            }
        }
    }

    private var coverageDisclaimer: some View {
        Label(localization.t("home.coverageDisclaimer"), systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 28)
            .accessibilityLabel(localization.t("home.coverageDisclaimer"))
    }

    private var importButtons: some View {
        let videoTitle = localization.t("home.pickPhotos")
        let photoTitle = localization.t("home.pickImages")
        return VStack(spacing: 12) {
            PhotosPicker(
                selection: $pickedPhotoItems,
                maxSelectionCount: ProductLimits.maximumPhotoBatchCount,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Label(photoTitle, systemImage: "photo.stack.fill")
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            PhotosPicker(
                selection: $pickedItem,
                matching: .videos,
                preferredItemEncoding: .current
            ) {
                Label(videoTitle, systemImage: "video.fill")
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
        .disabled(loadingImport)
    }

    private var importProgressOverlay: some View {
        VStack(spacing: 10) {
            if let importFraction, importFraction > 0 {
                ProgressView(value: importFraction)
                    .frame(width: 180)
                Text("\(Int(importFraction * 100))%")
                    .font(.headline.monospacedDigit())
            } else {
                ProgressView()
            }
            Text(localization.t("home.reading"))
            if activeImportProgress != nil || photoImportTask != nil {
                Button(localization.t("processing.cancel"), role: .cancel) {
                    cancelPhotoImport()
                }
                .font(.footnote)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var importErrorMessage: String {
        switch importErrorKey {
        case "error.fileTooLarge":
            localization.t("error.fileTooLarge")
        case "error.videoTooLong":
            localization.t("error.videoTooLong")
        case "error.invalidVideo":
            localization.t("error.invalidVideo")
        case "error.invalidPhoto":
            localization.t("error.invalidPhoto")
        default:
            ""
        }
    }

    private var isImportErrorPresented: Binding<Bool> {
        Binding(
            get: { importErrorKey != nil },
            set: { if !$0 { importErrorKey = nil } }
        )
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
    private func beginPhotoImport(_ item: PhotosPickerItem) {
        activeImportProgress?.cancel()
        importProgressTask?.cancel()
        loadingImport = true
        importFraction = nil

        let progress = item.loadTransferable(type: ImportedVideo.self) { result in
            Task { @MainActor in
                finishPhotoImport(item: item, result: result)
            }
        }
        activeImportProgress = progress
        importProgressTask = Task { @MainActor in
            while !Task.isCancelled, loadingImport {
                let fraction = progress.fractionCompleted
                importFraction = fraction > 0 ? min(fraction, 1) : nil
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    @MainActor
    private func cancelPhotoImport() {
        activeImportProgress?.cancel()
        photoImportTask?.cancel()
        photoImportTask = nil
        activeImportProgress = nil
        importProgressTask?.cancel()
        importProgressTask = nil
        importFraction = nil
        loadingImport = false
        pickedItem = nil
        pickedPhotoItems = []
    }

    @MainActor
    private func finishPhotoImport(
        item: PhotosPickerItem,
        result: Result<ImportedVideo?, Error>
    ) {
        importProgressTask?.cancel()
        importProgressTask = nil
        activeImportProgress = nil
        importFraction = nil
        loadingImport = false
        defer { pickedItem = nil }

        guard case let .success(video?) = result else { return }
        guard pickedItem == item else {
            try? FileManager.default.removeItem(at: video.url)
            return
        }
        Task {
            await acceptImportedVideo(with: video.url, ownsFile: true)
        }
    }

    @MainActor
    private func beginBatchPhotoImport(_ items: [PhotosPickerItem]) {
        photoImportTask?.cancel()
        loadingImport = true
        importFraction = 0
        photoImportTask = Task {
            var imported: [URL] = []
            defer {
                if Task.isCancelled {
                    for url in imported {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                loadingImport = false
                importFraction = nil
                pickedPhotoItems = []
                photoImportTask = nil
            }

            for (index, item) in items.enumerated() {
                if Task.isCancelled { return }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        continue
                    }
                    let pathExtension = item.supportedContentTypes
                        .compactMap(\.preferredFilenameExtension)
                        .first ?? "jpg"
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent("jingyin-photo-input-\(UUID().uuidString)")
                        .appendingPathExtension(pathExtension)
                    try data.write(to: destination, options: .atomic)
                    imported.append(destination)
                } catch {
                    continue
                }
                importFraction = Double(index + 1) / Double(items.count)
            }

            guard !Task.isCancelled else { return }
            guard !imported.isEmpty else {
                importErrorKey = "error.invalidPhoto"
                return
            }
            releaseImportedPhotos()
            ownedPhotoURLs = imported
            importedPhotos = PhotoBatchSelection(urls: imported)
        }
    }

    @MainActor
    private func importFile(_ source: URL) async {
        loadingImport = true
        importFraction = nil
        defer {
            loadingImport = false
            importFraction = nil
        }
        let scoped = source.startAccessingSecurityScopedResource()
        // Keep the security scope alive while the editor and exporter use the
        // file. This avoids a second full-size copy for Files imports.
        if scoped {
            await acceptImportedVideo(
                with: source,
                ownsFile: false,
                securityScoped: true
            )
        } else if let destination = try? ImportedVideo.makeDurableCopy(source) {
            // Debug launch arguments and app-external URLs do not always vend a
            // security scope. Preserve those before the provider releases them.
            await acceptImportedVideo(with: destination, ownsFile: true)
        }
    }

    @MainActor
    private func acceptImportedVideo(
        with url: URL,
        ownsFile: Bool,
        securityScoped: Bool = false
    ) async {
        if let validationErrorKey = await validateImportedVideo(at: url) {
            if securityScoped {
                url.stopAccessingSecurityScopedResource()
            }
            if ownsFile {
                try? FileManager.default.removeItem(at: url)
            }
            importErrorKey = validationErrorKey
            return
        }
        releaseImportedVideo()
        ownedInputURL = ownsFile ? url : nil
        securityScopedInputURL = securityScoped ? url : nil
        importedURL = url
    }

    @MainActor
    private func releaseImportedVideo() {
        if let securityScopedInputURL {
            securityScopedInputURL.stopAccessingSecurityScopedResource()
        }
        if let ownedInputURL {
            try? FileManager.default.removeItem(at: ownedInputURL)
        }
        ownedInputURL = nil
        securityScopedInputURL = nil
    }

    @MainActor
    private func releaseImportedPhotos() {
        for url in ownedPhotoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        ownedPhotoURLs = []
    }

    private func validateImportedVideo(at url: URL) async -> String? {
        let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let fileSize, fileSize > ProductLimits.maximumInputFileSizeBytes {
            return "error.fileTooLarge"
        }
        let duration = try? await AVURLAsset(url: url).load(.duration)
        guard let seconds = duration?.seconds, seconds.isFinite, seconds > 0 else {
            return "error.invalidVideo"
        }
        if seconds > ProductLimits.maximumInputDurationSeconds {
            return "error.videoTooLong"
        }
        return nil
    }
}

private struct PhotoBatchSelection: Identifiable, Equatable, Hashable {
    let id = UUID()
    let urls: [URL]
}

private struct ImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            Self(url: try claimTransferredFile(received.file))
        }
    }

    private static func claimTransferredFile(_ source: URL) throws -> URL {
        let destination = temporaryDestination(for: source)

        // The item provider owns `source` and may delete its path immediately
        // after this callback. A hard link gives the app its own durable name
        // for the same bytes without reading and writing the whole movie.
        if linkOrClone(source, to: destination) {
            return destination
        }

        do {
            // Photos gives FileRepresentation a disposable temporary file.
            // Moving it is instant on the same volume and avoids another copy.
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return destination
    }

    static func makeDurableCopy(_ source: URL) throws -> URL {
        let destination = temporaryDestination(for: source)
        if linkOrClone(source, to: destination) {
            return destination
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private static func temporaryDestination(for source: URL) -> URL {
        let pathExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("jingyin-input-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private static func linkOrClone(_ source: URL, to destination: URL) -> Bool {
        if (try? FileManager.default.linkItem(at: source, to: destination)) != nil {
            return true
        }

        // If hard links are unavailable, ask APFS for a copy-on-write clone.
        // This is also effectively instant and consumes blocks only when either
        // file changes.
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return -1 }
                return Int(clonefile(sourcePath, destinationPath, 0))
            }
        }
        return result == 0
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
