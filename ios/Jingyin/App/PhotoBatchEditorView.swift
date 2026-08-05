import SwiftUI
import UIKit

struct PhotoBatchEditorView: View {
    let inputURLs: [URL]

    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var drafts: [PhotoDraft]
    @State private var currentIndex = 0
    @State private var selectedTrackID: MaskTrack.ID?
    @State private var options: ProcessingOptions
    @State private var renderedPreview: UIImage?
    @State private var isAnalyzing = false
    @State private var isRenderingPreview = false
    @State private var isExporting = false
    @State private var isSaving = false
    @State private var savedCount = 0
    @State private var exportSuccessCount: Int?
    @State private var showPaywall = false
    @State private var showShare = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var previewTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var asciiRecentPairs = ASCIIColorRecentStore.load()
    @State private var showASCIIColorCustom = false
    @State private var isManualMaskExpanded = false
    @State private var isSubjectsExpanded = true
    @State private var isScopeExpanded = true
    @State private var isQualityExpanded = true
    @State private var isEffectExpanded = true

    init(inputURLs: [URL]) {
        self.inputURLs = inputURLs
        _drafts = State(initialValue: inputURLs.map { PhotoDraft(inputURL: $0) })
        _options = State(initialValue: ProcessingOptionsPreferenceStore.loadPhoto())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                batchHeader
                photoStrip
                preview
                maskActions
                subjectOptions
                scopeOptions
                qualityOptions
                effectOptions
                exportSection
            }
            .padding()
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.07))
        .navigationTitle(localization.t("photo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard drafts.allSatisfy({ $0.status == .pending }) else { return }
            analyzeAll()
        }
        .onChange(of: currentIndex) { _, _ in
            selectedTrackID = nil
            refreshPreview()
        }
        .onChange(of: options.style) { _, style in
            switch style {
            case .blur: options.strength = 32
            case .pixel: options.strength = 24
            case .ascii: options.strength = 14
            case .sticker: options.strength = 72
            }
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.scope) { _, _ in
            resetStickerIfUnavailable()
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.subjects) { _, _ in
            resetStickerIfUnavailable()
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.quality) { _, _ in
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.strength) { _, _ in
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.asciiForeground) { _, _ in
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.asciiBackground) { _, _ in
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.stickerEmoji) { _, _ in
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options) { _, options in
            ProcessingOptionsPreferenceStore.savePhoto(options)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(localization)
                .environmentObject(entitlements)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: outputURLs)
        }
        .alert(
            localization.t("photo.exportSuccess"),
            isPresented: Binding(
                get: { exportSuccessCount != nil },
                set: { if !$0 { exportSuccessCount = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let exportSuccessCount {
                Text(localization.format("photo.exportSuccessDetail", Int64(exportSuccessCount)))
            }
        }
        .onDisappear {
            analysisTask?.cancel()
            previewTask?.cancel()
            exportTask?.cancel()
            PhotoProcessor.removeOutputs(from: drafts)
        }
    }

    private var currentDraft: PhotoDraft? {
        drafts.indices.contains(currentIndex) ? drafts[currentIndex] : nil
    }

    private var currentTracks: Binding<[MaskTrack]> {
        Binding(
            get: {
                guard drafts.indices.contains(currentIndex) else { return [] }
                return drafts[currentIndex].maskGroups.map(\.track)
            },
            set: { value in
                guard drafts.indices.contains(currentIndex) else { return }
                invalidateOutputs(at: [currentIndex])
                for track in value {
                    guard let groupIndex = drafts[currentIndex].maskGroups
                        .firstIndex(where: { $0.id == track.id }) else {
                        continue
                    }
                    drafts[currentIndex].maskGroups[groupIndex].track = track
                }
            }
        )
    }

    private var outputURLs: [URL] {
        drafts.compactMap(\.outputURL)
    }

    private var batchHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.format("photo.batchCount", Int64(drafts.count)))
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isAnalyzing || isExporting {
                ProgressView()
                    .tint(.mint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        if isAnalyzing {
            let ready = drafts.filter { $0.status == .ready }.count
            return localization.format(
                "photo.analyzingProgress",
                Int64(ready),
                Int64(drafts.count)
            )
        }
        let failed = drafts.filter { $0.status == .failed }.count
        if failed > 0 {
            return localization.format("photo.failedCount", Int64(failed))
        }
        return localization.t("photo.reviewHint")
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    Button {
                        currentIndex = index
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let image = draft.previewImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.white.opacity(0.08))
                                        .overlay { ProgressView() }
                                }
                            }
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            statusBadge(draft.status)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(index == currentIndex ? .mint : .clear, lineWidth: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func statusBadge(_ status: PhotoWorkStatus) -> some View {
        let symbol: String
        let color: Color
        switch status {
        case .pending, .analyzing:
            symbol = "clock.fill"
            color = .gray
        case .ready:
            symbol = "checkmark.circle.fill"
            color = .mint
        case .exporting:
            symbol = "arrow.up.circle.fill"
            color = .blue
        case .completed:
            symbol = "checkmark.seal.fill"
            color = .green
        case .failed:
            symbol = "exclamationmark.triangle.fill"
            color = .red
        }
        return Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .padding(4)
            .background(.black.opacity(0.65), in: Circle())
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.black.opacity(0.35))

            if let image = renderedPreview ?? currentDraft?.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                MaskEditorOverlay(
                    tracks: currentTracks,
                    selectedTrackID: $selectedTrackID,
                    timeSeconds: 0,
                    videoDisplaySize: currentDraft?.displaySize,
                    onEditingBegan: {},
                    onEditingEnded: refreshPreview,
                    onDeleteTrack: deleteTrack
                )
            } else if currentDraft?.status == .failed {
                ContentUnavailableView(
                    localization.t("photo.invalid"),
                    systemImage: "photo.badge.exclamationmark"
                )
            } else {
                ProgressView(localization.t("photo.analyzing"))
            }

            if isRenderingPreview {
                ProgressView()
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var maskActions: some View {
        PhotoCollapsibleOptionSection(
            title: localization.t("editor.manualMasks"),
            systemImage: "square.dashed",
            meta: localization.format(
                "photo.maskCount",
                Int64(currentDraft?.maskGroups.count ?? 0)
            ),
            isExpanded: $isManualMaskExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button {
                    addManualMask(shape: .ellipse)
                } label: {
                    Label(localization.t("photo.addEllipse"), systemImage: "circle")
                }
                Button {
                    addManualMask(shape: .rectangle)
                } label: {
                    Label(localization.t("photo.addRectangle"), systemImage: "rectangle")
                }
            }
            .buttonStyle(.bordered)

            if let groups = currentDraft?.maskGroups, !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            Button {
                                selectedTrackID = group.id
                            } label: {
                                Label {
                                    Text(localization.format(
                                        "editor.maskItem",
                                        Int64(index + 1)
                                    ))
                                } icon: {
                                    Image(
                                        systemName: group.hasEdgeMask
                                            ? "wand.and.stars"
                                            : "square.dashed"
                                    )
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedTrackID == group.id
                                        ? Color.mint
                                        : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    selectedTrackID == group.id ? .black : .primary
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(localization.t(
                                group.hasEdgeMask
                                    ? "photo.mask.edge"
                                    : "photo.mask.fallback"
                            ))
                        }
                    }
                }
            }

            Text(localization.t("photo.maskHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subjectOptions: some View {
        PhotoCollapsibleOptionSection(
            title: localization.t("editor.subjects"),
            systemImage: "person.2",
            isExpanded: $isSubjectsExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button(localization.t("photo.redetect")) {
                    analyzeAll()
                }
                .disabled(isAnalyzing)
            }
            HStack(spacing: 8) {
                ForEach(SubjectKind.allCases) { subject in
                    Button {
                        options.toggleSubject(subject)
                    } label: {
                        Label(subject.title(localization.bundle), systemImage: subject.icon)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                options.subjects.contains(subject)
                                    ? Color.mint
                                    : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                            .foregroundStyle(
                                options.subjects.contains(subject) ? .black : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            }
        }
    }

    private var scopeOptions: some View {
        let bundle = localization.bundle
        return PhotoCollapsibleOptionSection(
            title: localization.t("editor.scope"),
            systemImage: "viewfinder",
            isExpanded: $isScopeExpanded
        ) {
            Picker(localization.t("editor.scope"), selection: $options.scope) {
                ForEach(MaskScope.allCases) {
                    Text($0.title(bundle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var qualityOptions: some View {
        let bundle = localization.bundle
        return PhotoCollapsibleOptionSection(
            title: localization.t("editor.quality"),
            systemImage: "speedometer",
            isExpanded: $isQualityExpanded
        ) {
            Picker(localization.t("editor.quality"), selection: $options.quality) {
                ForEach(QualityMode.allCases) {
                    Text($0.title(bundle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            Text(options.quality.detail(bundle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var effectOptions: some View {
        let bundle = localization.bundle
        return PhotoCollapsibleOptionSection(
            title: localization.t("editor.style"),
            systemImage: "wand.and.stars",
            isExpanded: $isEffectExpanded
        ) {
            HStack(spacing: 8) {
                ForEach(availableEffectStyles) { style in
                    Button {
                        options.style = style
                    } label: {
                        Text(style.title(bundle))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                options.style == style
                                    ? Color.mint
                                    : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                            .foregroundStyle(options.style == style ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Slider(value: $options.strength, in: strengthRange) {
                Text(localization.t("editor.strength"))
            } minimumValueLabel: {
                Text(localization.t("editor.weak"))
            } maximumValueLabel: {
                Text(localization.t("editor.strong"))
            }
            Text(strengthDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if options.style == .ascii {
                asciiColorControls(bundle: bundle)
            }
            if options.style == .sticker {
                stickerControls
            }
        }
    }

    private var strengthRange: ClosedRange<Double> {
        switch options.style {
        case .blur: 4...64
        case .pixel: 6...48
        case .ascii: 8...30
        case .sticker: 40...120
        }
    }

    private var availableEffectStyles: [EffectStyle] {
        EffectStyle.allCases.filter { $0 != .sticker || options.supportsFaceSticker }
    }

    private func resetStickerIfUnavailable() {
        guard options.style == .sticker, !options.supportsFaceSticker else { return }
        options.style = .pixel
        options.strength = 24
    }

    private var strengthDescription: String {
        let value = Int64(options.strength)
        switch options.style {
        case .blur:
            return localization.format("strength.blur", value)
        case .pixel:
            return localization.format("strength.pixel", value)
        case .ascii:
            return localization.format("strength.ascii", value)
        case .sticker:
            return localization.format("strength.sticker", value)
        }
    }

    private var stickerControls: some View {
        StickerEmojiPicker(
            title: localization.t("sticker.emoji"),
            selection: $options.stickerEmoji
        )
    }

    private var currentASCIIColorPair: ASCIIColorPair {
        ASCIIColorPair(
            foreground: options.asciiForeground,
            background: options.asciiBackground
        )
    }

    @ViewBuilder
    private func asciiColorControls(bundle: Bundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.t("ascii.color"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ASCIIColorTheme.all) { theme in
                        ASCIIColorSwatch(
                            pair: theme.pair,
                            isSelected: currentASCIIColorPair.matches(theme.pair),
                            accessibilityLabel: theme.title(bundle)
                        ) {
                            applyASCIIColorPair(theme.pair, remember: false)
                        }
                    }

                    if !asciiRecentPairs.isEmpty {
                        Divider()
                            .frame(height: 22)
                        ForEach(asciiRecentPairs) { pair in
                            ASCIIColorSwatch(
                                pair: pair,
                                isSelected: currentASCIIColorPair.matches(pair),
                                accessibilityLabel: localization.t("ascii.color.recent")
                            ) {
                                applyASCIIColorPair(pair, remember: false)
                            }
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showASCIIColorCustom.toggle()
                        }
                    } label: {
                        Image(systemName: showASCIIColorCustom ? "xmark.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.mint)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.t("ascii.color.custom"))
                }
            }

            if showASCIIColorCustom {
                ColorPicker(
                    localization.t("ascii.color.foreground"),
                    selection: asciiForegroundBinding,
                    supportsOpacity: false
                )
                ColorPicker(
                    localization.t("ascii.color.background"),
                    selection: asciiBackgroundBinding,
                    supportsOpacity: false
                )
            }
        }
        .padding(.top, 4)
    }

    private var asciiForegroundBinding: Binding<Color> {
        Binding(
            get: { color(from: options.asciiForeground) },
            set: { newValue in
                options.asciiForeground = effectRGBA(from: newValue)
                rememberCurrentASCIIColors()
            }
        )
    }

    private var asciiBackgroundBinding: Binding<Color> {
        Binding(
            get: { color(from: options.asciiBackground) },
            set: { newValue in
                options.asciiBackground = effectRGBA(from: newValue)
                rememberCurrentASCIIColors()
            }
        )
    }

    private func applyASCIIColorPair(_ pair: ASCIIColorPair, remember: Bool) {
        options.asciiForeground = pair.foreground
        options.asciiBackground = pair.background
        if remember {
            rememberCurrentASCIIColors()
        }
    }

    private func rememberCurrentASCIIColors() {
        ASCIIColorRecentStore.remember(currentASCIIColorPair)
        asciiRecentPairs = ASCIIColorRecentStore.load()
    }

    private func color(from rgba: EffectRGBA) -> Color {
        Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    private func effectRGBA(from color: Color) -> EffectRGBA {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return .asciiDefaultForeground
        }
        return EffectRGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }

    private var exportSection: some View {
        VStack(spacing: 12) {
            if !entitlements.isUnlocked && drafts.count > 1 {
                PurchaseStatusCard {
                    showPaywall = true
                }
            }

            Button {
                exportPhotos()
            } label: {
                Label(
                    entitlements.isUnlocked
                        ? localization.t("photo.exportBatch")
                        : localization.t("photo.exportCurrent"),
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
            .disabled(isAnalyzing || isExporting || currentDraft?.status == .failed)

            if !outputURLs.isEmpty {
                HStack {
                    Button {
                        saveOutputs()
                    } label: {
                        Label(
                            savedCount > 0
                                ? localization.format("photo.savedCount", Int64(savedCount))
                                : localization.t("photo.save"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .disabled(isSaving)

                    Button {
                        showShare = true
                    } label: {
                        Label(localization.t("processing.share"), systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func analyzeAll() {
        analysisTask?.cancel()
        previewTask?.cancel()
        invalidateOutputs(at: Array(drafts.indices))
        renderedPreview = nil
        isAnalyzing = true
        let subjects = options.subjects
        analysisTask = Task {
            for index in drafts.indices {
                if Task.isCancelled { break }
                let manualGroups = drafts[index].maskGroups.filter {
                    $0.track.source == .manual
                }
                drafts[index].status = .analyzing
                do {
                    let analysis = try await PhotoProcessor.analyze(
                        url: drafts[index].inputURL,
                        subjects: subjects
                    )
                    drafts[index].previewImage = analysis.previewImage
                    drafts[index].displaySize = analysis.displaySize
                    drafts[index].maskGroups = analysis.maskGroups + manualGroups
                    drafts[index].maskPlanes = analysis.maskPlanes
                    drafts[index].status = .ready
                    if index == currentIndex {
                        selectedTrackID = nil
                        refreshPreview()
                    }
                } catch {
                    drafts[index].status = .failed
                }
            }
            isAnalyzing = false
            refreshPreview()
        }
    }

    private func refreshPreview() {
        previewTask?.cancel()
        renderedPreview = nil
        guard let currentDraft, currentDraft.status != .failed else { return }
        let expectedID = currentDraft.id
        let renderOptions = PhotoProcessor.optionsForPhoto(
            options,
            maskGroups: currentDraft.maskGroups
        )
        isRenderingPreview = true
        previewTask = Task {
            defer { isRenderingPreview = false }
            guard let rendered = try? await PhotoProcessor.renderPreview(
                url: currentDraft.inputURL,
                options: renderOptions,
                maskGroups: currentDraft.maskGroups,
                maskPlanes: currentDraft.maskPlanes
            ), !Task.isCancelled,
               drafts.indices.contains(currentIndex),
               drafts[currentIndex].id == expectedID else {
                return
            }
            renderedPreview = rendered.image
        }
    }

    private func addManualMask(shape: MaskTrackShape) {
        guard drafts.indices.contains(currentIndex) else { return }
        let track = MaskTrack(
            shape: shape,
            source: .manual,
            keyframes: [
                MaskKeyframe(
                    timeSeconds: 0,
                    rect: NormalizedVideoRect(
                        x: 0.30,
                        y: 0.30,
                        width: 0.40,
                        height: 0.30
                    )
                )
            ]
        )
        drafts[currentIndex].maskGroups.append(PhotoMaskGroup(track: track))
        selectedTrackID = track.id
        invalidateOutputs(at: [currentIndex])
        refreshPreview()
    }

    private func deleteTrack(_ id: MaskTrack.ID) {
        guard drafts.indices.contains(currentIndex) else { return }
        drafts[currentIndex].maskGroups.removeAll { $0.id == id }
        if selectedTrackID == id {
            selectedTrackID = nil
        }
        invalidateOutputs(at: [currentIndex])
        refreshPreview()
    }

    private func invalidateOutputs(at indices: [Int]) {
        for index in indices where drafts.indices.contains(index) {
            if let outputURL = drafts[index].outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
            drafts[index].outputURL = nil
            if drafts[index].status == .completed {
                drafts[index].status = .ready
            }
        }
        savedCount = 0
    }

    private func exportPhotos() {
        exportTask?.cancel()
        savedCount = 0
        let targets: [PhotoDraft]
        if entitlements.isUnlocked {
            targets = drafts.filter { $0.status != .failed }
        } else if let currentDraft, currentDraft.status != .failed {
            targets = [currentDraft]
        } else {
            return
        }
        for target in targets {
            if let index = drafts.firstIndex(where: { $0.id == target.id }) {
                if let oldOutput = drafts[index].outputURL {
                    try? FileManager.default.removeItem(at: oldOutput)
                }
                drafts[index].outputURL = nil
                drafts[index].status = .exporting
            }
        }
        isExporting = true
        let access = entitlements.access
        exportTask = Task {
            let results = await PhotoProcessor.export(
                drafts: targets,
                options: options,
                access: access
            )
            var successCount = 0
            for target in targets {
                guard let index = drafts.firstIndex(where: { $0.id == target.id }) else {
                    continue
                }
                switch results[target.id] {
                case let .success(url):
                    drafts[index].outputURL = url
                    drafts[index].status = .completed
                    successCount += 1
                case .failure, .none:
                    drafts[index].status = .failed
                }
            }
            isExporting = false
            if successCount > 0 {
                exportSuccessCount = successCount
            }
        }
    }

    private func saveOutputs() {
        let urls = outputURLs
        guard !urls.isEmpty else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoProcessor.saveToPhotos(urls)
                savedCount = urls.count
            } catch {
                savedCount = 0
            }
        }
    }
}

private struct PhotoCollapsibleOptionSection<Content: View>: View {
    let title: String
    let systemImage: String
    var meta: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 13 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    if let meta {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
