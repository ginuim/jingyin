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
    let onReturnHome: () -> Void

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
    @State private var exportResult: PhotoExportResult?
    @State private var showPaywall = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var previewTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var asciiRecentPairs = ASCIIColorRecentStore.load()
    @State private var showASCIIColorCustom = false
    @State private var selectedTool: PhotoEditorTool? = .effect

    private static let parameterPanelHeight: CGFloat = 160

    init(inputURLs: [URL], onReturnHome: @escaping () -> Void = {}) {
        self.inputURLs = inputURLs
        self.onReturnHome = onReturnHome
        _drafts = State(initialValue: inputURLs.map { PhotoDraft(inputURL: $0) })
        _options = State(initialValue: ProcessingOptionsPreferenceStore.loadPhoto())
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                photoStrip
                Divider()
                    .overlay(AppPalette.divider)

                preview
                    .padding(12)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)

                toolBar

                if let selectedTool {
                    parameterPanel(
                        for: selectedTool,
                        height: min(Self.parameterPanelHeight, proxy.size.height * 0.48)
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .foregroundStyle(AppPalette.primaryText)
        .background(AppPalette.background)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportPhotos()
                } label: {
                    ZStack {
                        Text(localization.t("photo.exportAction"))
                            .font(.subheadline.weight(.semibold))
                            .opacity(isExporting ? 0 : 1)
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
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
        .navigationDestination(item: $exportResult) { result in
            PhotoExportSuccessView(result: result, onReturnHome: onReturnHome)
                .environmentObject(localization)
                .environmentObject(entitlements)
        }
        .onDisappear(perform: handleDisappear)
    }

    private var currentDraft: PhotoDraft? {
        drafts.indices.contains(currentIndex) ? drafts[currentIndex] : nil
    }

    private func handleDisappear() {
        analysisTask?.cancel()
        previewTask?.cancel()
        exportTask?.cancel()
        // Pushing the export result also makes this editor disappear. The
        // result screen still needs these temporary files for save/share.
        if exportResult == nil {
            PhotoProcessor.removeOutputs(from: drafts)
        }
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
                                        .fill(AppPalette.elevatedSurface)
                                        .overlay { ProgressView() }
                                }
                            }
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            statusBadge(draft.status)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(
                                    index == currentIndex
                                        ? AppPalette.accent.primary
                                        : AppPalette.divider,
                                    lineWidth: index == currentIndex ? 3 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(AppPalette.surface)
    }

    private func statusBadge(_ status: PhotoWorkStatus) -> some View {
        let symbol: String
        let color: Color
        switch status {
        case .pending, .analyzing:
            symbol = "clock.fill"
            color = AppPalette.secondaryText
        case .ready:
            symbol = "checkmark.circle.fill"
            color = AppPalette.accent.primary
        case .exporting:
            symbol = "arrow.up.circle.fill"
            color = AppPalette.accent.outline
        case .completed:
            symbol = "checkmark.seal.fill"
            color = AppPalette.success
        case .failed:
            symbol = "exclamationmark.triangle.fill"
            color = AppPalette.destructive
        }
        return Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .padding(4)
            .background(AppPalette.mediaScrim, in: Circle())
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(AppPalette.mediaCanvas)

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
                    onDeleteTrack: deleteTrack,
                    accentColor: AppPalette.accent.primary
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
                    .tint(AppPalette.accent.primary)
                    .padding(12)
                    .background(AppPalette.elevatedSurface, in: Circle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 160)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func parameterPanel(for tool: PhotoEditorTool, height: CGFloat) -> some View {
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
        .padding(.top, 8)
        .padding(.bottom, 4)
        // The sticker picker is the tallest standard tool. Keeping every tool
        // at that height prevents the editor from jumping during tool changes.
        .frame(height: height)
        .background(AppPalette.elevatedSurface)
        .overlay(alignment: .top) {
            Divider().overlay(AppPalette.divider)
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
                                isSelected ? AppPalette.accent.softFill : .clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(
                                        isSelected ? AppPalette.accent.primary : .clear,
                                        lineWidth: 1.5
                                    )
                            }

                        Text(tool.title(localization))
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(
                        isSelected ? AppPalette.accent.primary : AppPalette.secondaryText
                    )
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
        .background(AppPalette.surface)
        .overlay(alignment: .top) {
            Divider().overlay(AppPalette.divider)
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
                .foregroundStyle(AppPalette.secondaryText)
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
                                        ? AppPalette.accent.primary
                                        : AppPalette.elevatedSurface,
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    selectedTrackID == group.id
                                        ? AppPalette.accent.foreground
                                        : AppPalette.primaryText
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
                .foregroundStyle(AppPalette.secondaryText)
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
                                    ? AppPalette.accent.primary
                                    : AppPalette.elevatedSurface,
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                            .foregroundStyle(
                                options.subjects.contains(subject)
                                    ? AppPalette.accent.foreground
                                    : AppPalette.primaryText
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
                        AppPalette.accent.softFill,
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(AppPalette.accent.outline.opacity(0.7), lineWidth: 1)
                    }
                    .foregroundStyle(AppPalette.accent.primary)
            }
            .buttonStyle(.plain)
            .disabled(isAnalyzing)
            .opacity(isAnalyzing ? 0.45 : 1)
        }
    }

    private var scopeOptions: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 12) {
            singleSelectRow(MaskScope.allCases, selected: options.scope, title: { $0.title(bundle) }) {
                options.scope = $0
            }
        }
    }

    private var qualityOptions: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 12) {
            singleSelectRow(QualityMode.allCases, selected: options.quality, title: { $0.title(bundle) }) {
                options.quality = $0
            }
            Text(options.quality.detail(bundle))
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func singleSelectRow<Item: Identifiable>(
        _ items: [Item],
        selected: Item.ID,
        title: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void
    ) -> some View where Item.ID: Equatable {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(title(item))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            item.id == selected
                                ? AppPalette.accent.primary
                                : AppPalette.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .foregroundStyle(
                            item.id == selected
                                ? AppPalette.accent.foreground
                                : AppPalette.primaryText
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var effectOptions: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 12) {
            singleSelectRow(availableEffectStyles, selected: options.style, title: { $0.title(bundle) }) {
                options.style = $0
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
            selection: $options.stickerEmoji,
            accentColor: AppPalette.accent.primary
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
                            accessibilityLabel: theme.title(bundle),
                            selectionColor: AppPalette.accent.primary
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
                                accessibilityLabel: localization.t("ascii.color.recent"),
                                selectionColor: AppPalette.accent.primary
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
                            .foregroundStyle(AppPalette.accent.primary)
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
    }

    private func exportPhotos() {
        exportTask?.cancel()
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
                let urls = drafts.compactMap(\.outputURL)
                exportResult = PhotoExportResult(outputURLs: urls)
            }
        }
    }
}
