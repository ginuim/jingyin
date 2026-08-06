import SwiftUI
import UIKit

private enum PhotoEditorTool: String, CaseIterable, Identifiable {
    case subjects
    case scope
    case effect
    case masks
    case quality

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .subjects: "person.2"
        case .scope: "viewfinder"
        case .effect: "wand.and.stars"
        case .masks: "square.dashed"
        case .quality: "speedometer"
        }
    }

    @MainActor
    func title(_ localization: LocalizationManager) -> String {
        switch self {
        case .subjects: localization.t("editor.subjects")
        case .scope: localization.t("editor.scope")
        case .effect: localization.t("editor.style")
        case .masks: localization.t("editor.manualMasks")
        case .quality: localization.t("editor.quality")
        }
    }
}

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
    @State private var selectedTool: PhotoEditorTool? = .effect

    init(inputURLs: [URL]) {
        self.inputURLs = inputURLs
        _drafts = State(initialValue: inputURLs.map { PhotoDraft(inputURL: $0) })
        _options = State(initialValue: ProcessingOptionsPreferenceStore.loadPhoto())
    }

    var body: some View {
        VStack(spacing: 0) {
            photoStrip
            Divider()
                .overlay(.white.opacity(0.12))

            preview
                .padding(12)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)

            toolBar

            if let selectedTool {
                parameterPanel(for: selectedTool)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.07))
        .navigationTitle(localization.t("photo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entitlements.isUnlocked && drafts.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPaywall = true
                    } label: {
                        Image(systemName: "crown")
                    }
                    .accessibilityLabel(localization.t("purchase.unlock"))
                }
            }
            if !outputURLs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveOutputs()
                    } label: {
                        Image(systemName: savedCount > 0 ? "checkmark.circle.fill" : "square.and.arrow.down")
                    }
                    .disabled(isSaving)
                    .accessibilityLabel(
                        savedCount > 0
                            ? localization.format("photo.savedCount", Int64(savedCount))
                            : localization.t("photo.save")
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(localization.t("processing.share"))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportPhotos()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Text(localization.t("photo.exportAction"))
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .disabled(isAnalyzing || isExporting || currentDraft?.status == .failed)
                .accessibilityLabel(
                    entitlements.isUnlocked
                        ? localization.t("photo.exportBatch")
                        : localization.t("photo.exportCurrent")
                )
            }
        }
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
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            statusBadge(draft.status)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(index == currentIndex ? .mint : .white.opacity(0.18), lineWidth: index == currentIndex ? 3 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.black.opacity(0.18))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 210)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func parameterPanel(for tool: PhotoEditorTool) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Group {
                switch tool {
                case .subjects:
                    subjectOptions
                case .scope:
                    scopeOptions
                case .effect:
                    effectOptions
                case .masks:
                    maskActions
                case .quality:
                    qualityOptions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Fixed drawer height so switching tools does not jump the preview.
        // Overflow scrolls inside; keep it tall enough for effect / mask controls.
        .frame(height: 220)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var toolBar: some View {
        HStack(spacing: 0) {
            ForEach(PhotoEditorTool.allCases) { tool in
                let isSelected = selectedTool == tool
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTool = isSelected ? nil : tool
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                            .frame(width: 32, height: 28)
                            .background(
                                isSelected ? Color.mint.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isSelected ? Color.mint : .clear, lineWidth: 1.5)
                            }

                        Text(tool.title(localization))
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isSelected ? Color.mint : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var maskActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localization.format(
                    "photo.maskCount",
                    Int64(currentDraft?.maskGroups.count ?? 0)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var subjectOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Button {
                analyzeAll()
            } label: {
                Label(localization.t("photo.redetect"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Color.mint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Color.mint.opacity(0.55), lineWidth: 1)
                    }
                    .foregroundStyle(Color.mint)
            }
            .buttonStyle(.plain)
            .disabled(isAnalyzing)
            .opacity(isAnalyzing ? 0.45 : 1)
        }
    }

    private var scopeOptions: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 10) {
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
        return VStack(alignment: .leading, spacing: 10) {
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
        return VStack(alignment: .leading, spacing: 12) {
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
            if options.style != .sticker {
                Slider(value: $options.strength, in: strengthRange) {
                    Text(localization.t("editor.strength"))
                } minimumValueLabel: {
                    Text(localization.t("editor.weak"))
                } maximumValueLabel: {
                    Text(localization.t("editor.strong"))
                }
            }

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
