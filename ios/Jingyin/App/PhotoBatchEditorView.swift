import SwiftUI
import UIKit

private enum PhotoEditorTool: String, CaseIterable, Identifiable {
    case subjects
    case scope
    case effect
    case masks

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .subjects: "person.2"
        case .scope: "viewfinder"
        case .effect: "wand.and.stars"
        case .masks: "square.dashed"
        }
    }

    @MainActor
    func title(_ localization: LocalizationManager) -> String {
        switch self {
        case .subjects: localization.t("editor.subjects")
        case .scope: localization.t("editor.scope")
        case .effect: localization.t("editor.style")
        case .masks: localization.t("photo.adjustRegions")
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
    @State private var isDrawingFreehandMask = false
    @State private var brushWidth = 0.08
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
    @State private var activeExportID: UUID?
    @State private var exportCompletedCount = 0
    @State private var exportTotalCount = 0
    @State private var pendingDeleteTrackID: MaskTrack.ID?
    @State private var showCancelExportConfirmation = false
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
            ZStack {
                VStack(spacing: 0) {
                    photoStrip
                    Label(
                        localization.t("photo.reviewHint"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppPalette.surface)
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
                .allowsHitTesting(!isExporting)

                if isExporting {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                    exportProgress
                        .frame(maxWidth: 300)
                        .padding(24)
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
                    if isExporting {
                        showCancelExportConfirmation = true
                    } else {
                        exportPhotos()
                    }
                } label: {
                    Text(exportButtonTitle)
                    .font(.subheadline.weight(.semibold))
                }
                .disabled(
                    !isExporting
                        && (isAnalyzing || currentDraft?.status == .failed)
                )
                .accessibilityLabel(
                    isExporting
                        ? localization.t("processing.cancel")
                        : entitlements.isUnlocked
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
            isDrawingFreehandMask = false
            refreshPreview()
        }
        .onChange(of: selectedTrackID) { _, id in
            guard let id,
                  let path = currentDraft?.maskGroups
                    .first(where: { $0.id == id })?.manualPath else { return }
            brushWidth = path.strokeWidth
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
            // Full-frame processing does not use subject or manual mask
            // geometry. Keep those editing affordances out of the preview so
            // stale detected-face bounds do not remain over the image.
            selectedTrackID = nil
            isDrawingFreehandMask = false
            resetStickerIfUnavailable()
            invalidateOutputs(at: Array(drafts.indices))
            refreshPreview()
        }
        .onChange(of: options.subjects) { _, _ in
            resetStickerIfUnavailable()
            analyzeAll()
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
        .confirmationDialog(
            localization.t("photo.confirmDeleteMaskTitle"),
            isPresented: Binding(
                get: { pendingDeleteTrackID != nil },
                set: { if !$0 { pendingDeleteTrackID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localization.t("common.cancel"), role: .cancel) { pendingDeleteTrackID = nil }
            Button(localization.t("common.delete"), role: .destructive) {
                if let id = pendingDeleteTrackID { deleteTrack(id) }
                pendingDeleteTrackID = nil
            }
        } message: {
            Text(localization.t("photo.confirmDeleteMaskMessage"))
        }
        .confirmationDialog(
            localization.t("processing.confirmCancelTitle"),
            isPresented: $showCancelExportConfirmation,
            titleVisibility: .visible
        ) {
            Button(localization.t("common.cancel"), role: .cancel) {}
            Button(localization.t("processing.cancel"), role: .destructive) { cancelPhotoExport() }
        } message: {
            Text(localization.t("processing.confirmCancelMessage"))
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

    private var exportableCount: Int {
        drafts.filter { $0.status != .failed }.count
    }

    private var exportButtonTitle: String {
        if isExporting {
            return localization.t("processing.cancel")
        }
        if entitlements.isUnlocked {
            return localization.format("photo.exportCount", Int64(exportableCount))
        }
        return localization.t("photo.exportCurrent")
    }

    private var exportProgress: some View {
        let total = max(exportTotalCount, 1)
        let fraction = Double(exportCompletedCount) / Double(total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(localization.t("photo.exporting"), systemImage: "photo.stack")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(localization.format("photo.exportProgress", Int64(exportCompletedCount), Int64(total)))
                    .font(.caption)
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .tint(AppPalette.accent.primary)

            Button(localization.t("processing.cancel")) {
                showCancelExportConfirmation = true
            }
            .buttonStyle(TextButtonStyle(role: .destructive))
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
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
                return drafts[currentIndex].maskGroups
                    .filter { !$0.hasManualPath }
                    .map(\.track)
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

                            statusBadge(draft.status, isReviewed: draft.isReviewed)
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

    private func statusBadge(_ status: PhotoWorkStatus, isReviewed: Bool) -> some View {
        let symbol: String
        let color: Color
        switch status {
        case .pending, .analyzing:
            symbol = "clock.fill"
            color = AppPalette.secondaryText
        case .ready:
            symbol = isReviewed ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            color = isReviewed ? AppPalette.success : AppPalette.accent.primary
        case .exporting:
            symbol = "arrow.up.circle.fill"
            color = AppPalette.accent.outline
        case .completed:
            symbol = isReviewed ? "checkmark.seal.fill" : "exclamationmark.circle.fill"
            color = isReviewed ? AppPalette.success : AppPalette.accent.primary
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

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTrackID = nil
                    }
                    .allowsHitTesting(!isDrawingFreehandMask)

                if options.scope != .full {
                    MaskEditorOverlay(
                        tracks: currentTracks,
                        selectedTrackID: $selectedTrackID,
                        timeSeconds: 0,
                        currentTimeSeconds: { 0 },
                        videoDisplaySize: currentDraft?.displaySize,
                        onEditingBegan: {},
                        onEditingEnded: refreshPreview,
                        onDeleteTrack: requestDeleteTrack,
                        accentColor: AppPalette.accent.primary
                    )
                    .allowsHitTesting(!isDrawingFreehandMask)

                    PhotoFreehandMaskOverlay(
                        groups: currentDraft?.maskGroups ?? [],
                        selectedTrackID: $selectedTrackID,
                        isDrawing: $isDrawingFreehandMask,
                        displaySize: currentDraft?.displaySize,
                        brushWidth: brushWidth,
                        onComplete: addManualPath,
                        onDelete: requestDeleteTrack,
                        accentColor: AppPalette.accent.primary
                    )
                }

                if isDrawingFreehandMask {
                    VStack {
                        HStack(spacing: 10) {
                            Text(localization.t("photo.drawMaskHint"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.primaryText)
                            Button(localization.t("common.cancel")) {
                                isDrawingFreehandMask = false
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 10)
                        Spacer()
                    }
                }
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
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    tool == .masks
                        ? localization.t("photo.currentOnly")
                        : localization.format("photo.applyAll", Int64(drafts.count)),
                    systemImage: tool == .masks ? "photo" : "photo.stack"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)

                switch tool {
                case .subjects:
                    subjectOptions
                case .scope:
                    scopeOptions
                case .effect:
                    effectOptions
                case .masks:
                    maskActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep every tool panel at the same height, but center compact
            // tools in that space instead of leaving a large empty footer.
            // Taller tools can still scroll inside the fixed panel.
            .frame(
                minHeight: max(height - 16, 0),
                alignment: .topLeading
            )
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        // The sticker picker is the tallest standard tool. Every tool keeps
        // this height so switching tools never moves the preview.
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
                Menu {
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
                    Button {
                        selectedTrackID = nil
                        isDrawingFreehandMask = true
                    } label: {
                        Label(localization.t("photo.addFreehand"), systemImage: "scribble.variable")
                    }
                } label: {
                    Label(localization.t("photo.addMask"), systemImage: "plus")
                }
            }
            .buttonStyle(.bordered)

            if !automaticMaskGroups.isEmpty {
                maskGroupSection(
                    title: localization.t("photo.automaticRegions"),
                    groups: automaticMaskGroups
                )
            }

            if !manualMaskGroups.isEmpty {
                maskGroupSection(
                    title: localization.t("photo.manualRegions"),
                    groups: manualMaskGroups
                )
            }

            if shouldShowBrushSize {
                HStack(spacing: 10) {
                    Image(systemName: "paintbrush.pointed")
                        .foregroundStyle(AppPalette.secondaryText)
                    Text(localization.t("photo.brushSize"))
                        .font(.caption.weight(.semibold))
                    Slider(
                        value: $brushWidth,
                        in: 0.02...0.20,
                        onEditingChanged: { editing in
                            if !editing {
                                updateSelectedBrushWidth()
                            }
                        }
                    )
                    .accessibilityLabel(localization.t("photo.brushSize"))
                    Text("\(Int((brushWidth * 100).rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppPalette.secondaryText)
                        .frame(width: 22, alignment: .trailing)
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
                        VStack(spacing: 5) {
                            Image(systemName: subject.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(subject.title(localization.bundle))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
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

            if options.subjects.contains(.pet) {
                Text(localization.t("editor.petHint"))
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var automaticMaskGroups: [PhotoMaskGroup] {
        currentDraft?.maskGroups.filter { $0.track.source != .manual } ?? []
    }

    private var manualMaskGroups: [PhotoMaskGroup] {
        currentDraft?.maskGroups.filter { $0.track.source == .manual } ?? []
    }

    private var shouldShowBrushSize: Bool {
        if isDrawingFreehandMask { return true }
        guard let selectedTrackID else { return false }
        return currentDraft?.maskGroups.first(where: { $0.id == selectedTrackID })?.hasManualPath == true
    }

    private func maskGroupSection(
        title: String,
        groups: [PhotoMaskGroup]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups) { group in
                        let number = (currentDraft?.maskGroups.firstIndex(where: { $0.id == group.id }) ?? 0) + 1
                        Button {
                            selectedTrackID = group.id
                        } label: {
                            Label {
                                Text(localization.format("editor.maskItem", Int64(number)))
                            } icon: {
                                Image(systemName: maskGroupIcon(group))
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedTrackID == group.id
                                    ? AppPalette.accent.primary
                                    : AppPalette.surface,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedTrackID == group.id
                                    ? AppPalette.accent.foreground
                                    : AppPalette.primaryText
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(localization.t(maskGroupAccessibilityKey(group)))
                    }
                }
            }
        }
    }

    private func maskGroupIcon(_ group: PhotoMaskGroup) -> String {
        if group.hasManualPath {
            return "scribble.variable"
        }
        if group.track.source == .detectedFace {
            return "face.smiling"
        }
        return group.hasEdgeMask ? "wand.and.stars" : "square.dashed"
    }

    private func maskGroupAccessibilityKey(
        _ group: PhotoMaskGroup
    ) -> String.LocalizationValue {
        if group.hasManualPath {
            return "photo.mask.freehand"
        }
        if group.track.source == .detectedFace {
            return "photo.mask.faceRange"
        }
        return group.hasEdgeMask ? "photo.mask.edge" : "photo.mask.fallback"
    }

    private var scopeOptions: some View {
        let bundle = localization.bundle
        return HStack(spacing: 8) {
            ForEach(MaskScope.allCases) { scope in
                let isSelected = options.scope == scope
                Button {
                    options.scope = scope
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: scopeIcon(scope))
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(height: 20)
                        Text(scope.title(bundle))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 4)
                    .background(
                        isSelected ? AppPalette.accent.softFill : AppPalette.surface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? AppPalette.accent.primary : AppPalette.divider,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                    .foregroundStyle(
                        isSelected ? AppPalette.accent.primary : AppPalette.primaryText
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func scopeIcon(_ scope: MaskScope) -> String {
        switch scope {
        case .subjects: "person.fill"
        case .background: "rectangle.on.rectangle"
        case .full: "rectangle.fill"
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
        return VStack(alignment: .leading, spacing: 8) {
            singleSelectRow(availableEffectStyles, selected: options.style, title: { $0.title(bundle) }) {
                options.style = $0
            }
            if options.style != .sticker {
                VStack(spacing: 5) {
                    HStack {
                        Text(localization.t("editor.strength"))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(options.strength.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppPalette.accent.primary)
                    }

                    Slider(value: $options.strength, in: strengthRange) {
                        Text(localization.t("editor.strength"))
                    } minimumValueLabel: {
                        Text(localization.t("editor.weak"))
                            .font(.caption)
                    } maximumValueLabel: {
                        Text(localization.t("editor.strong"))
                            .font(.caption)
                    }
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
        for index in drafts.indices {
            drafts[index].maskGroups.removeAll {
                $0.track.source != .manual
            }
            drafts[index].maskPlanes = []
        }
        renderedPreview = nil
        isAnalyzing = true
        let subjects = options.subjects
        analysisTask = Task {
            for index in drafts.indices {
                guard !Task.isCancelled else { return }
                let manualGroups = drafts[index].maskGroups.filter {
                    $0.track.source == .manual
                }
                drafts[index].status = .analyzing
                do {
                    let analysis = try await PhotoProcessor.analyze(
                        url: drafts[index].inputURL,
                        subjects: subjects
                    )
                    guard !Task.isCancelled else { return }
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
                    guard !Task.isCancelled else { return }
                    drafts[index].status = .failed
                }
            }
            guard !Task.isCancelled else { return }
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
            drafts[currentIndex].isReviewed = true
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

    private func addManualPath(_ path: NormalizedMaskPath) {
        guard drafts.indices.contains(currentIndex) else { return }
        let track = MaskTrack(
            shape: .rectangle,
            source: .manual,
            keyframes: [
                MaskKeyframe(timeSeconds: 0, rect: path.boundingRect)
            ]
        )
        drafts[currentIndex].maskGroups.append(
            PhotoMaskGroup(track: track, manualPath: path)
        )
        selectedTrackID = track.id
        invalidateOutputs(at: [currentIndex])
        refreshPreview()
    }

    private func updateSelectedBrushWidth() {
        guard drafts.indices.contains(currentIndex),
              let id = selectedTrackID,
              let index = drafts[currentIndex].maskGroups
                .firstIndex(where: { $0.id == id }),
              let oldPath = drafts[currentIndex].maskGroups[index].manualPath,
              let updatedPath = NormalizedMaskPath(
                points: oldPath.points,
                strokeWidth: brushWidth
              ) else { return }
        drafts[currentIndex].maskGroups[index].manualPath = updatedPath
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

    private func requestDeleteTrack(_ id: MaskTrack.ID) {
        pendingDeleteTrackID = id
    }

    private func invalidateOutputs(at indices: [Int]) {
        for index in indices where drafts.indices.contains(index) {
            if let outputURL = drafts[index].outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
            drafts[index].outputURL = nil
            drafts[index].isReviewed = false
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
        exportCompletedCount = 0
        exportTotalCount = targets.count
        let access = entitlements.access
        let exportID = UUID()
        activeExportID = exportID
        exportTask = Task {
            let results = await PhotoProcessor.export(
                drafts: targets,
                options: options,
                access: access,
                progress: { completed, total in
                    await MainActor.run {
                        guard activeExportID == exportID else { return }
                        exportCompletedCount = completed
                        exportTotalCount = total
                    }
                }
            )
            guard !Task.isCancelled, activeExportID == exportID else {
                let staleOutputs = results.values.compactMap { result -> URL? in
                    guard case let .success(url) = result else { return nil }
                    return url
                }
                PhotoProcessor.removeOutputs(at: staleOutputs)
                return
            }
            var successCount = 0
            var successfulURLs: [URL] = []
            for target in targets {
                guard let index = drafts.firstIndex(where: { $0.id == target.id }) else {
                    continue
                }
                switch results[target.id] {
                case let .success(url):
                    drafts[index].outputURL = url
                    drafts[index].status = .completed
                    successCount += 1
                    successfulURLs.append(url)
                case .failure, .none:
                    drafts[index].status = .failed
                }
            }
            activeExportID = nil
            exportTask = nil
            isExporting = false
            exportCompletedCount = 0
            exportTotalCount = 0
            if successCount > 0 {
                exportResult = PhotoExportResult(
                    outputURLs: successfulURLs,
                    totalDraftCount: drafts.count,
                    limitedToCurrentPhoto: !entitlements.isUnlocked
                )
            }
        }
    }

    private func cancelPhotoExport() {
        activeExportID = nil
        exportTask?.cancel()
        exportTask = nil
        resetExportingDrafts()
        isExporting = false
        exportCompletedCount = 0
        exportTotalCount = 0
    }

    private func resetExportingDrafts() {
        for index in drafts.indices where drafts[index].status == .exporting {
            drafts[index].status = .ready
        }
    }

}
