import AVFoundation
import AVKit
import CoreImage
import SwiftUI
import UIKit

private enum EditorDestructiveAction: Identifiable {
    case keyframe
    case mask(MaskTrack.ID)

    var id: String {
        switch self {
        case .keyframe: "keyframe"
        case .mask(let id): "mask-\(id)"
        }
    }
}

struct EditorView: View {
    let videoURL: URL
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var player: AVPlayer
    @State private var options: ProcessingOptions
    @State private var showProcessing = false
    @State private var showExportSettings = false
    @State private var showPaywall = false
    @State private var sourceMetadata: SourceVideoMetadata?
    @State private var previewGeneration = 0
    @State private var maskPreviewRevision = 0
    @State private var playheadSeconds = 0.0
    @State private var selectedMaskTrackID: MaskTrack.ID?
    @State private var inspectedEntities: [MaskEntity] = []
    @State private var inspectedConfiguration = ""
    @State private var inspectedTime = -1.0
    @State private var inspectingEntities = false
    @State private var inspectionFailed = false
    @State private var selectedEntityID: MaskEntity.ID?
    @State private var showManualMaskEditor = false
    @State private var showFullScreenMaskEditor = false
    @State private var faceDetectionSnapshot: FaceDetectionSnapshot?
    @State private var showFaceSelection = false
    @State private var pendingDestructiveAction: EditorDestructiveAction?
    @State private var isDetectingFaces = false
    @State private var faceDetectionMessage: String?
    @State private var faceTrackingTasks: [MaskTrack.ID: Task<Void, Never>] = [:]
    @StateObject private var voicePreview = VoicePreviewEngine()
    @State private var statusObserver: NSKeyValueObservation?
    @State private var jumpObserver: NSObjectProtocol?
    @State private var asciiRecentPairs = ASCIIColorRecentStore.load()
    @State private var showASCIIColorCustom = false
    @State private var maskHistory: [MaskEditSnapshot] = []
    @State private var committedMasks = MaskEditSnapshot(tracks: [], selection: nil)
    @State private var editFeedback: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expandedParameters = false
    @State private var sourceDuration = 0.0
    @State private var selectedTool: VideoEditorTool = .subjects

    init(videoURL: URL) {
        self.videoURL = videoURL
        _player = State(initialValue: AVPlayer(url: videoURL))
        _options = State(initialValue: ProcessingOptionsPreferenceStore.loadVideo())
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                videoPlayerSection(
                    height: max(
                        120, geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.25 : 0.40)))
                toolBar
                ScrollView {
                    settings
                        .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text(configurationSummary)
                    .font(.footnote)
                    .foregroundStyle(AppPalette.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    player.pause()
                    voicePreview.stop(unload: true)
                    showExportSettings = true
                } label: {
                    Text(localization.t("editor.next"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    hasTrackingInProgress
                        || (options.scope == .background && options.subjects.isEmpty
                            && options.maskTracks.isEmpty)
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(AppPalette.background)
        }
        .foregroundStyle(AppPalette.primaryText)
        .background(AppPalette.background)
        .navigationTitle(localization.t("editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showProcessing) {
            ProcessingView(
                videoURL: videoURL,
                options: options,
                access: entitlements.access
            )
        }
        .sheet(isPresented: $expandedParameters) {
            NavigationStack {
                ScrollView { settings.padding(20) }
                    .navigationTitle(localization.t(selectedTool.titleKey))
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(localization.t("editor.done")) { expandedParameters = false }
                    } }
            }.presentationDetents([.large])
        }
        .sheet(isPresented: $showExportSettings) {
            ExportSettingsSheet(
                options: $options,
                metadata: sourceMetadata,
                sourceDuration: sourceDuration,
                onExport: {
                    showExportSettings = false
                    showProcessing = true
                }
            )
            .environmentObject(localization)
            .environmentObject(entitlements)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(localization)
                .environmentObject(entitlements)
        }
        .fullScreenCover(isPresented: $showFullScreenMaskEditor) {
            FullScreenMaskEditorView(
                player: player,
                tracks: $options.maskTracks,
                selectedTrackID: $selectedMaskTrackID,
                playheadSeconds: $playheadSeconds,
                videoDisplaySize: sourceMetadata?.displaySize,
                timelineMarkers: manualMaskTimelineMarkers,
                timelineRanges: manualMaskTimelineRanges,
                isMaskEditingEnabled: options.scope != .full,
                onEditingBegan: {
                    player.pause()
                    voicePreview.pause()
                },
                onDeleteTrack: requestDeleteMask,
                onEditingEnded: finishMaskEditing
            ) {
                manualPanel
            }
            .environmentObject(localization)
        }
        .sheet(isPresented: $showFaceSelection) {
            if let faceDetectionSnapshot {
                FaceSelectionView(
                    snapshot: faceDetectionSnapshot,
                    onConfirm: {
                        addDetectedFaceTracks(
                            candidates: $0,
                            snapshot: faceDetectionSnapshot
                        )
                    }
                )
                .environmentObject(localization)
            }
        }
        .confirmationDialog(
            destructiveConfirmationTitle,
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localization.t("common.cancel"), role: .cancel) {
                pendingDestructiveAction = nil
            }
            Button(localization.t("common.delete"), role: .destructive) {
                performPendingDestructiveAction()
            }
        } message: {
            Text(destructiveConfirmationMessage)
        }
        .task(id: entityInspectionToken) { await inspectCurrentEntities() }
        .task(id: videoEffectToken) {
            await applyPreview()
        }
        .task {
            await loadSourceMetadata()
        }
        .task {
            // Simulator smoke-test hook. It keeps long-video verification
            // repeatable without affecting normal launches.
            let arguments = ProcessInfo.processInfo.arguments
            while !entitlements.isReady, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(25))
            }
            if arguments.contains("-demoExportSettings") {
                while sourceMetadata == nil, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                showExportSettings = true
            } else if arguments.contains("-demoProcess") {
                options.scope = .full
                options.quality = .fast
                options.audio = .original
                options.exportResolution = .p480
                options.exportFrameRate = 24
                player.pause()
                showProcessing = true
            }
        }
        .onAppear {
            MediaPlaybackSession.activate()
            installPlayerObservers()
            applyAudioMode()
        }
        .onChange(of: options.audio) { _, _ in
            applyAudioMode()
        }
        .onChange(of: options.voicePitch) { _, pitch in
            VoicePitchStore.save(pitch)
            voicePreview.setPitch(pitch)
        }
        .onChange(of: options) { _, options in
            ProcessingOptionsPreferenceStore.saveVideo(options)
        }
        .onChange(of: selectedTool) { _, tool in
            showManualMaskEditor = tool == .manual
            if tool == .manual {
                player.pause()
                voicePreview.pause()
            }
        }
        .onDisappear {
            for task in faceTrackingTasks.values {
                task.cancel()
            }
            faceTrackingTasks.removeAll()
            removePlayerObservers()
            player.pause()
            voicePreview.stop(unload: true)
            MediaPlaybackSession.deactivate()
        }
    }

    /// Exclude audio/pitch so voice slider does not rebuild the mask composition.
    private var entityInspectionToken: String {
        // Selection uses only a paused, current-frame snapshot; moving playback never shows old boxes.
        "\(selectedTool.rawValue)|\(showFullScreenMaskEditor)|\(playheadSeconds)|\(options.scope.rawValue)|\(options.subjects.map(\.rawValue).sorted())"
    }

    private var entitiesMatchPlayhead: Bool {
        player.timeControlStatus == .paused && abs(inspectedTime - playheadSeconds) < 0.08
    }

    @MainActor private func inspectCurrentEntities() async {
        guard selectedTool == .subjects, !showFullScreenMaskEditor,
            options.scope != .full, !options.subjects.isEmpty,
            player.timeControlStatus == .paused else { return }
        let configuration = "\(options.scope.rawValue)|\(options.subjects.map(\.rawValue).sorted())"
        if entitiesMatchPlayhead && inspectedConfiguration == configuration { return }
        inspectedTime = -1
        inspectedEntities = []
        let time = playheadSeconds
        inspectingEntities = true
        inspectionFailed = false
        let processor = FrameEffectProcessor(options: options)
        await processor.warmUp()
        guard !Task.isCancelled else { return }
        let result = await syncMaskEntities(
            using: processor, asset: AVURLAsset(url: videoURL),
            at: CMTime(seconds: time, preferredTimescale: 600))
        guard !Task.isCancelled, abs(playheadSeconds - time) < 0.08 else { return }
        inspectedEntities = result ?? []
        inspectedTime = time
        inspectedConfiguration = configuration
        if let selectedEntityID, !inspectedEntities.contains(where: { $0.id == selectedEntityID }) {
            self.selectedEntityID = nil
        }
        inspectionFailed = result == nil
        inspectingEntities = false
    }

    private var videoEffectToken: String {
        let subjects = options.subjects.map(\.rawValue).sorted().joined(separator: ",")
        let fg = options.asciiForeground
        let bg = options.asciiBackground
        let entities = options.maskEntities
            .map { "\($0.id.uuidString):\($0.isEnabled ? 1 : 0)" }
            .sorted()
            .joined(separator: ",")
        return "\(options.quality.rawValue)|\(options.scope.rawValue)|\(options.style.rawValue)|\(options.strength)|\(options.stickerEmoji.rawValue)|\(subjects)|\(maskPreviewRevision)|\(fg.r),\(fg.g),\(fg.b),\(fg.a)|\(bg.r),\(bg.g),\(bg.b),\(bg.a)|\(entities)"
    }

    private func videoPlayerSection(height: CGFloat) -> some View {
        ControlledVideoPlayer(
            player: player,
            thumbnailURL: videoURL,
            timelineMarkers: manualMaskTimelineMarkers,
            timelineRanges: manualMaskTimelineRanges,
            onTimeChanged: { playheadSeconds = $0 },
            onFullScreen: {
                showFullScreenMaskEditor = true
            }
        ) {
            BareVideoPlayer(player: player)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    if selectedTool == .subjects && options.scope != .full && entitiesMatchPlayhead {
                        GeometryReader { proxy in
                            let bounds = VideoCoordinateSpace.aspectFitBounds(
                                displaySize: sourceMetadata?.displaySize, in: proxy.size)
                            ForEach(Array(inspectedEntities.enumerated()), id: \.element.id) { index, entity in
                                let rect = entity.lastRect.rect(inPreviewBounds: bounds)
                                Button {
                                    selectedEntityID = entity.id
                                } label: {
                                    Rectangle().stroke(
                                        selectedEntityID == entity.id
                                            ? AppPalette.accent.primary : AppPalette.maskOutline,
                                        style: StrokeStyle(
                                            lineWidth: selectedEntityID == entity.id ? 3 : 1,
                                            dash: selectedEntityID == entity.id ? [] : [5, 4])
                                    )
                                    .overlay(alignment: .topLeading) {
                                        Text("\(index + 1)").font(.caption.bold())
                                            .padding(4).background(AppPalette.mediaScrim)
                                            .foregroundStyle(AppPalette.maskOutline)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .accessibilityLabel(localization.format("editor.entityItem", Int64(index + 1)))
                                .accessibilityAddTraits(selectedEntityID == entity.id ? .isSelected : [])
                            }
                        }
                    }
                    if showManualMaskEditor && options.scope != .full {
                        MaskEditorOverlay(
                            tracks: $options.maskTracks,
                            selectedTrackID: $selectedMaskTrackID,
                            timeSeconds: playheadSeconds,
                            videoDisplaySize: sourceMetadata?.displaySize,
                            onEditingBegan: {
                                player.pause()
                                voicePreview.pause()
                            },
                            onEditingEnded: finishMaskEditing,
                            onDeleteTrack: requestDeleteMask
                        )
                    }
                }
        }
    }

    private var settings: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.t(selectedTool.titleKey)).font(.headline)
                Spacer()
                if !expandedParameters {
                    Button { expandedParameters = true } label: {
                        Label(localization.t("editor.expandParameters"), systemImage: "chevron.up")
                    }.buttonStyle(TextButtonStyle())
                }
            }
            switch selectedTool {
            case .subjects: subjectsPanel
            case .manual: manualPanel
            case .style: stylePanel
            case .audio: audioPanel
            }
        }
    }

    private var subjectsPanel: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 8) {
                presetButton(.face)
                presetButton(.person)
            }

            Picker(localization.t("editor.scope"), selection: $options.scope) {
                ForEach(MaskScope.allCases) {
                    Text($0.title(bundle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: options.scope) { _, _ in
                resetStickerIfUnavailable()
            }
            if options.scope != .full {
                Toggle(
                    localization.t("editor.automatic"),
                    isOn: Binding(
                        get: { !options.subjects.isEmpty },
                        set: { enabled in
                            options.subjects = enabled ? [.person] : []
                            options.maskEntities = []
                            selectedEntityID = nil
                            resetStickerIfUnavailable()
                        }
                    ))

                HStack(spacing: 10) {
                    ForEach(SubjectKind.allCases) { subject in
                        let isSelected = options.subjects.contains(subject)
                        Button {
                            toggle(subject)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 7) {
                                    Image(systemName: subject.icon)
                                    Text(subject.title(bundle))
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)

                                Image(
                                    systemName: isSelected
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    isSelected ? AppPalette.accent.foreground : AppPalette.secondaryText
                                )
                                .padding(6)
                            }
                            .background(
                                isSelected
                                    ? AppPalette.accent.primary
                                    : AppPalette.elevatedSurface,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(isSelected ? AppPalette.accent.foreground : AppPalette.primaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }

                if options.subjects.contains(.pet) {
                    Text(localization.t("editor.petHint"))
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if inspectingEntities {
                    ProgressView(localization.t("editor.inspecting"))
                } else if entitiesMatchPlayhead {
                    if inspectedEntities.isEmpty {
                        Text(localization.t(inspectionFailed ? "editor.inspectionFailed" : "editor.noEntities"))
                            .font(.footnote)
                    } else {
                        entitySelector
                    }
                } else {
                    Text(localization.t("editor.pauseToInspect")).font(.footnote)
                }

                Text(localization.t("editor.entityHint"))
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if options.scope == .background && options.subjects.isEmpty && options.maskTracks.isEmpty {
                    Text(localization.t("editor.backgroundEmpty")).font(.footnote)
                }
            }
        }
    }

    private var stylePanel: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 12) {

            Picker(localization.t("editor.style"), selection: $options.style) {
                ForEach(availableEffectStyles) {
                    Text($0.title(bundle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: options.style) { _, style in
                switch style {
                case .blur: options.strength = 32
                case .pixel: options.strength = 24
                case .ascii: options.strength = 14
                case .sticker: options.strength = 72
                }
            }
            Slider(value: $options.strength, in: strengthRange) {
                Text(localization.t(options.style == .sticker ? "editor.size" : "editor.strength"))
            } minimumValueLabel: {
                Text(localization.t(options.style == .sticker ? "editor.small" : "editor.weak"))
            } maximumValueLabel: {
                Text(localization.t(options.style == .sticker ? "editor.large" : "editor.strong"))
            }
            Text(strengthDescription)
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if options.style == .ascii {
                asciiColorControls(bundle: bundle)
            }
            if options.style == .sticker {
                stickerControls
            }
        }
    }

    private var audioPanel: some View {
        let bundle = localization.bundle
        return VStack(alignment: .leading, spacing: 12) {

            Picker(localization.t("editor.audio"), selection: $options.audio) {
                ForEach(AudioMode.allCases) {
                    Text($0.title(bundle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)

            if options.audio == .voice {
                HStack {
                    Text(localization.t("editor.pitchLow"))
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                    Slider(
                        value: Binding(
                            get: { Double(options.voicePitch) },
                            set: { options.voicePitch = Int($0.rounded()) }
                        ),
                        in: Double(VoicePitchStore.range.lowerBound)...Double(VoicePitchStore.range.upperBound),
                        step: 1
                    )
                    Text(localization.t("editor.pitchHigh"))
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }

            if options.audio == .voice {
                Text(localization.t("editor.pitchHint"))
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                voicePreviewStatus
            }
        }
    }

    private func presetButton(_ kind: SubjectKind) -> some View {
        Button {
            options.scope = .subjects
            options.subjects = [kind]
            options.maskEntities = []
            selectedEntityID = nil
            resetStickerIfUnavailable()
        } label: {
            Label(
                kind.title(localization.bundle),
                systemImage: options.scope == .subjects && options.subjects == [kind]
                    ? "checkmark.circle.fill" : kind.icon
            )
            .frame(maxWidth: .infinity)
        }.buttonStyle(TextButtonStyle())
    }

    private var manualPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if options.scope == .full {
                Text(localization.t("editor.manualNotNeeded"))
            } else {

                HStack(spacing: 10) {
                    Button {
                        addManualMask(shape: .ellipse)
                    } label: {
                        Label(
                            localization.t("editor.addEllipse"),
                            systemImage: "plus.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextButtonStyle())

                    Button {
                        addManualMask(shape: .rectangle)
                    } label: {
                        Label(
                            localization.t("editor.addRectangle"),
                            systemImage: "plus.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextButtonStyle())
                }

                if !options.maskTracks.isEmpty {
                    maskSelector
                }

                if let selectedMaskIndex {
                    maskVisibilityMenu
                    Toggle(
                        localization.t("editor.animatePosition"),
                        isOn: Binding(
                            get: { options.maskTracks.first(where: { $0.id == selectedMaskTrackID })?.effectivePositionMode == .animated },
                            set: { setPositionMode($0) }
                        ))
                    Text(
                        localization.t(
                            options.maskTracks[selectedMaskIndex].effectivePositionMode == .animated
                                ? "editor.animatedHint" : "editor.fixedHint")
                    )
                    .font(.footnote).foregroundStyle(AppPalette.secondaryText)
                    HStack {
                        Button {
                            jumpToRecord(forward: false)
                        } label: {
                            Label(localization.t("editor.previousRecord"), systemImage: "backward.end")
                        }
                        Button {
                            jumpToRecord(forward: true)
                        } label: {
                            Label(localization.t("editor.nextRecord"), systemImage: "forward.end")
                        }
                    }.buttonStyle(TextButtonStyle())
                    Button(role: .destructive) {
                        deleteMask(id: options.maskTracks[selectedMaskIndex].id)
                    } label: {
                        Label(localization.t("editor.deleteEntireMask"), systemImage: "trash")
                    }.buttonStyle(TextButtonStyle(role: .destructive))
                    HStack(spacing: 10) {
                        Button(action: shrinkSelectedMask) {
                            Label(
                                localization.t("editor.shrinkMask"),
                                systemImage: "minus.magnifyingglass"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TextButtonStyle())

                        Button(action: enlargeSelectedMask) {
                            Label(
                                localization.t("editor.enlargeMask"),
                                systemImage: "plus.magnifyingglass"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TextButtonStyle())
                    }

                    HStack(spacing: 10) {
                        positionRecordsMenu
                            .frame(maxWidth: .infinity)
                            .disabled(options.maskTracks[selectedMaskIndex].effectivePositionMode != .animated)
                    }

                    if let selectedFaceTrack {
                        faceTrackingStatus(selectedFaceTrack)
                    }
                }

                Button(action: undoMaskEdit) {
                    Label(localization.t("editor.undo"), systemImage: "arrow.uturn.backward")
                }.buttonStyle(TextButtonStyle()).disabled(maskHistory.isEmpty)
                if let editFeedback { Text(editFeedback).font(.footnote) }
                Text(
                    localization.t(
                        options.scope == .background ? "editor.backgroundManualHint" : "editor.manualHelp")
                )
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                Label(
                    localization.t("editor.keyframeTimelineHint"),
                    systemImage: "timeline.selection"
                )
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var configurationSummary: String {
        let subjects = SubjectKind.allCases.filter { options.subjects.contains($0) }
            .map { $0.title(localization.bundle) }.joined(separator: " + ")
        let target =
            options.scope == .subjects
            ? (subjects.isEmpty ? localization.t("editor.manualTool") : subjects)
            : options.scope.title(localization.bundle)
                + (options.scope == .background ? " · " + subjects : "")
        return [
            target, options.style.title(localization.bundle),
            options.audioMeta(bundle: localization.bundle),
        ].joined(separator: " · ")
    }

    private var toolBar: some View {
        HStack(spacing: 8) {
            ForEach(VideoEditorTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.icon).font(.system(size: 18))
                        Text(localization.t(tool.titleKey)).font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.vertical, 4)
                    .background(
                        selectedTool == tool ? AppPalette.accent.softFill : AppPalette.surface,
                        in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var voicePreviewStatus: some View {
        if voicePreview.isPreparing {
            ProgressView(localization.t("editor.preparingVoice"))
        } else if voicePreview.isPreviewUnsupported {
            Text(localization.t("error.previewUnsupported"))
                .foregroundStyle(AppPalette.secondaryText)
        }
    }

    private func toggle(_ subject: SubjectKind) {
        options.toggleSubject(subject)
        resetStickerIfUnavailable()
        options.maskEntities.removeAll { !options.subjects.contains($0.kind) }
        if let selectedEntityID,
           !options.maskEntities.contains(where: { $0.id == selectedEntityID }) {
            self.selectedEntityID = nil
        }
    }

    private var entitySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(inspectedEntities.enumerated()), id: \.element.id) { index, entity in
                        Button {
                            selectedEntityID = entity.id
                        } label: {
                            Label {
                                Text(
                                    localization.format(
                                        "editor.entityItem",
                                        Int64(index + 1)
                                    ))
                            } icon: {
                                Image(systemName: entity.kind.icon)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedEntityID == entity.id
                                    ? AppPalette.accent.primary
                                    : AppPalette.elevatedSurface,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedEntityID == entity.id
                                    ? AppPalette.accent.foreground
                                    : (entity.isEnabled ? AppPalette.primaryText : AppPalette.secondaryText)
                            )
                            .opacity(entity.isEnabled ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            localization.t(
                                entity.isEnabled ? "editor.entityOn" : "editor.entityOff"
                            )
                        )
                    }
                }
            }

            if let selectedEntityID,
                let entity = inspectedEntities.first(where: { $0.id == selectedEntityID })
            {
                let enabled =
                    options.maskEntities.first(where: { $0.id == selectedEntityID })?.isEnabled
                    ?? entity.isEnabled
                Button {
                    if let index = options.maskEntities.firstIndex(where: { $0.id == selectedEntityID }) {
                        options.maskEntities[index].isEnabled.toggle()
                    } else {
                        var changed = entity
                        changed.isEnabled = !enabled
                        options.maskEntities.append(changed)
                    }
                } label: {
                    Label(
                        localization.t(enabled ? "editor.entityDisable" : "editor.entityEnable"),
                        systemImage: enabled ? "eye.slash" : "eye")
                }.buttonStyle(TextButtonStyle())
            }
        }
        .padding(.top, 4)
    }

    private var manualMaskCountLabel: String? {
        guard !options.maskTracks.isEmpty else { return nil }
        return localization.format(
            "editor.maskCount",
            Int64(options.maskTracks.count)
        )
    }

    private var manualMaskTimelineMarkers: [VideoTimelineMarker] {
        guard showManualMaskEditor || showFullScreenMaskEditor else { return [] }
        return options.maskTracks.flatMap { track in
            track.keyframes
                .filter { $0.origin == .manual }
                .map { keyframe in
                    VideoTimelineMarker(
                        id: keyframe.id,
                        timeSeconds: keyframe.timeSeconds,
                        isSelected: track.id == selectedMaskTrackID
                    )
                }
        }
    }

    private var manualMaskTimelineRanges: [VideoTimelineRange] {
        guard showManualMaskEditor || showFullScreenMaskEditor else { return [] }
        return options.maskTracks.compactMap { track in
            guard track.activeFromSeconds != nil || track.activeUntilSeconds != nil else {
                return nil
            }
            return VideoTimelineRange(
                id: track.id,
                startSeconds: track.activeFromSeconds ?? 0,
                endSeconds: track.activeUntilSeconds,
                isSelected: track.id == selectedMaskTrackID
            )
        }
    }

    private var maskSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.maskTracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.pause()
                        voicePreview.pause()
                        selectedMaskTrackID = track.id
                    } label: {
                        Label(
                            localization.format("editor.maskItem", Int64(index + 1)),
                            systemImage: track.source == .detectedFace
                                ? "person.crop.circle"
                                : (
                                    track.shape == .ellipse
                                        ? "circle.dashed"
                                        : "rectangle.dashed"
                                )
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            selectedMaskTrackID == track.id
                                ? AppPalette.accent.primary
                                : AppPalette.elevatedSurface,
                            in: Capsule()
                        )
                        .foregroundStyle(selectedMaskTrackID == track.id ? AppPalette.accent.foreground : AppPalette.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var maskVisibilityMenu: some View {
        Menu {
            Button {
                setSelectedMaskStart()
            } label: {
                Label(
                    localization.t("editor.startShowingHere"),
                    systemImage: "arrow.right.to.line"
                )
            }

            Button {
                setSelectedMaskEnd()
            } label: {
                Label(
                    localization.t("editor.stopShowingHere"),
                    systemImage: "arrow.left.to.line"
                )
            }

            Divider()

            Button {
                showSelectedMaskForWholeTimeline()
            } label: {
                Label(
                    localization.t("editor.showForEntireVideo"),
                    systemImage: "arrow.left.and.right"
                )
            }
        } label: {
            VStack(spacing: 2) {
                Label(
                    localization.t("editor.visibility"),
                    systemImage: "clock"
                )
                .font(.caption.bold())
                Text(selectedMaskVisibilitySummary)
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TextButtonStyle())
    }

    private var positionRecordsMenu: some View {
        Menu {
            Button(action: insertKeyframe) {
                Label(
                    localization.t("editor.recordPosition"),
                    systemImage: "diamond.fill"
                )
            }

            Button(
                role: .destructive,
                action: requestDeleteCurrentKeyframe
            ) {
                Label(
                    localization.t("editor.deletePositionRecord"),
                    systemImage: "diamond.slash"
                )
            }
            .disabled(!canDeleteCurrentKeyframe)
        } label: {
            Label(
                localization.t("editor.positionRecords"),
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TextButtonStyle())
    }

    private var selectedMaskVisibilitySummary: String {
        guard let selectedMaskIndex else {
            return localization.t("editor.showForEntireVideo")
        }
        let track = options.maskTracks[selectedMaskIndex]
        switch (track.activeFromSeconds, track.activeUntilSeconds) {
        case (let start?, let end?):
            return localization.format(
                "editor.visibilityRange",
                formatTimestamp(start),
                formatTimestamp(end)
            )
        case (let start?, nil):
            return localization.format(
                "editor.visibilityFrom",
                formatTimestamp(start)
            )
        case (nil, let end?):
            return localization.format(
                "editor.visibilityUntil",
                formatTimestamp(end)
            )
        case (nil, nil):
            return localization.t("editor.showForEntireVideo")
        }
    }

    private func addManualMask(shape: MaskTrackShape) {
        player.pause()
        voicePreview.pause()
        let track = MaskTrack(
            shape: shape,
            keyframes: [
                MaskKeyframe(
                    timeSeconds: editingTimeSeconds,
                    rect: NormalizedVideoRect(
                        x: 0.3,
                        y: 0.3,
                        width: 0.4,
                        height: 0.4
                    )
                )
            ]
        )
        options.maskTracks.append(track)
        selectedMaskTrackID = track.id
        refreshMaskPreview()
    }

    @MainActor
    private func detectFacesAtCurrentFrame() async {
        // Deliberately retained as a prototype only. The launch TODO keeps
        // specified-face tracking hidden until its device matrix is reliable.
        guard !isDetectingFaces else { return }
        player.pause()
        voicePreview.pause()
        isDetectingFaces = true
        faceDetectionMessage = nil
        defer { isDetectingFaces = false }

        do {
            let snapshot = try await FaceTrackingService.detectFaces(
                in: videoURL,
                at: editingTimeSeconds
            )
            faceDetectionSnapshot = snapshot
            guard !snapshot.candidates.isEmpty else {
                faceDetectionMessage = localization.t("faceSelection.noneHint")
                return
            }
            showFaceSelection = true
        } catch is CancellationError {
            return
        } catch {
            faceDetectionMessage = localization.t("faceSelection.failed")
        }
    }

    private func addDetectedFaceTracks(
        candidates: [DetectedFaceCandidate],
        snapshot: FaceDetectionSnapshot
    ) {
        guard !candidates.isEmpty else { return }
        player.pause()
        voicePreview.pause()
        showManualMaskEditor = true
        // Individually selected faces replace the broad automatic person/face
        // mask while leaving independently selected pet masking untouched.
        options.subjects.remove(.person)
        options.subjects.remove(.face)

        for candidate in candidates {
            let track = MaskTrack(
                shape: .ellipse,
                source: .detectedFace,
                sourceIdentifier: candidate.id.uuidString,
                activeFromSeconds: snapshot.actualTimeSeconds,
                trackingState: .tracking,
                keyframes: [
                    MaskKeyframe(
                        timeSeconds: snapshot.actualTimeSeconds,
                        rect: candidate.coverageRect
                    )
                ]
            )
            options.maskTracks.append(track)
            selectedMaskTrackID = track.id
            startTracking(
                trackID: track.id,
                from: snapshot.actualTimeSeconds,
                initialVisionBoundingBox: candidate.visionBoundingBox
            )
        }
        faceDetectionMessage = nil
        refreshMaskPreview()
    }

    private func startTracking(
        trackID: MaskTrack.ID,
        from timeSeconds: TimeInterval,
        initialVisionBoundingBox: CGRect
    ) {
        faceTrackingTasks[trackID]?.cancel()
        if let index = options.maskTracks.firstIndex(where: { $0.id == trackID }) {
            options.maskTracks[index].trackingState = .tracking
            options.maskTracks[index].trackingLostAtSeconds = nil
        }

        faceTrackingTasks[trackID] = Task {
            defer {
                faceTrackingTasks[trackID] = nil
            }
            do {
                let result = try await FaceTrackingService.trackFace(
                    in: videoURL,
                    from: timeSeconds,
                    initialVisionBoundingBox: initialVisionBoundingBox
                )
                guard !Task.isCancelled,
                    let index = options.maskTracks.firstIndex(where: {
                        $0.id == trackID
                    })
                else {
                    return
                }
                options.maskTracks[index].applyTrackingResult(
                    keyframes: result.keyframes,
                    lostAtSeconds: result.lostAtSeconds
                )
                refreshMaskPreview()
            } catch is CancellationError {
                return
            } catch {
                guard
                    let index = options.maskTracks.firstIndex(where: {
                        $0.id == trackID
                    })
                else {
                    return
                }
                options.maskTracks[index].trackingState = .lost
                options.maskTracks[index].trackingLostAtSeconds = timeSeconds
                refreshMaskPreview()
            }
        }
    }

    private func retrySelectedFaceTracking() {
        guard let selectedMaskIndex,
              options.maskTracks[selectedMaskIndex].source == .detectedFace,
              let rect = options.maskTracks[selectedMaskIndex]
                .keyframedRect(at: editingTimeSeconds) else {
            return
        }
        let trackID = options.maskTracks[selectedMaskIndex].id
        options.maskTracks[selectedMaskIndex].removeKeyframes(
            after: editingTimeSeconds
        )
        options.maskTracks[selectedMaskIndex].setKeyframe(
            MaskKeyframe(timeSeconds: editingTimeSeconds, rect: rect)
        )
        let trackingRect = rect
            .scaledAroundCenter(by: 0.68, minimumDimension: 0.02)
            .visionBoundingBox
        startTracking(
            trackID: trackID,
            from: editingTimeSeconds,
            initialVisionBoundingBox: trackingRect
        )
        refreshMaskPreview()
    }

    private var editingTimeSeconds: TimeInterval {
        let current = player.currentTime().seconds
        return current.isFinite ? max(0, current) : max(0, playheadSeconds)
    }

    private var selectedMaskIndex: Int? {
        guard let selectedMaskTrackID else { return nil }
        return options.maskTracks.firstIndex { $0.id == selectedMaskTrackID }
    }

    private var selectedFaceTrack: MaskTrack? {
        guard let selectedMaskIndex,
              options.maskTracks[selectedMaskIndex].source == .detectedFace else {
            return nil
        }
        return options.maskTracks[selectedMaskIndex]
    }

    private var hasTrackingInProgress: Bool {
        options.maskTracks.contains { $0.trackingState == .tracking }
    }

    @ViewBuilder
    private func faceTrackingStatus(_ track: MaskTrack) -> some View {
        switch track.trackingState {
        case .tracking:
            ProgressView(localization.t("tracking.inProgress"))
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tracked:
            Label(
                localization.t("tracking.complete"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(AppPalette.accent.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .lost:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    localization.format(
                        "tracking.lostAt",
                        formatTimestamp(track.trackingLostAtSeconds ?? editingTimeSeconds)
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(AppPalette.warning)
                .fixedSize(horizontal: false, vertical: true)

                Text(localization.t("tracking.correctionHint"))
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: retrySelectedFaceTracking) {
                    Label(
                        localization.t("tracking.continue"),
                        systemImage: "scope"
                    )
                }
                .buttonStyle(TextButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .needsRetracking:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    localization.t("tracking.correctionSaved"),
                    systemImage: "diamond.fill"
                )
                .font(.caption)
                .foregroundStyle(AppPalette.accent.primary)

                Button(action: retrySelectedFaceTracking) {
                    Label(
                        localization.t("tracking.continue"),
                        systemImage: "scope"
                    )
                }
                .buttonStyle(TextButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .notTracked:
            EmptyView()
        }
    }

    private var currentKeyframe: MaskKeyframe? {
        guard let selectedMaskIndex else { return nil }
        let time = editingTimeSeconds
        return options.maskTracks[selectedMaskIndex].keyframes.min {
            abs($0.timeSeconds - time) < abs($1.timeSeconds - time)
        }.flatMap {
            abs($0.timeSeconds - time) <= 0.12 ? $0 : nil
        }
    }

    private var canDeleteCurrentKeyframe: Bool {
        guard let selectedMaskIndex else { return false }
        return options.maskTracks[selectedMaskIndex].keyframes.count > 1
            && currentKeyframe != nil
    }

    private func insertKeyframe() {
        guard let selectedMaskIndex,
            let rect = options.maskTracks[selectedMaskIndex]
                .keyframedRect(at: editingTimeSeconds)
        else {
            return
        }
        player.pause()
        voicePreview.pause()
        guard options.maskTracks[selectedMaskIndex].effectivePositionMode == .animated else { return }
        options.maskTracks[selectedMaskIndex].setKeyframe(
            MaskKeyframe(timeSeconds: editingTimeSeconds, rect: rect)
        )
        refreshMaskPreview()
    }

    private func requestDeleteCurrentKeyframe() {
        guard currentKeyframe != nil, canDeleteCurrentKeyframe else { return }
        deleteCurrentKeyframe()
    }

    private func deleteCurrentKeyframe() {
        guard let selectedMaskIndex,
              options.maskTracks[selectedMaskIndex].keyframes.count > 1,
              let keyframe = currentKeyframe else {
            return
        }
        options.maskTracks[selectedMaskIndex].removeKeyframe(id: keyframe.id)
        refreshMaskPreview()
    }

    private func shrinkSelectedMask() {
        scaleSelectedMask(by: 0.9)
    }

    private func enlargeSelectedMask() {
        scaleSelectedMask(by: 1.1)
    }

    private func scaleSelectedMask(by factor: Double) {
        guard let selectedMaskIndex,
            let rect = options.maskTracks[selectedMaskIndex]
                .keyframedRect(at: editingTimeSeconds)
        else {
            return
        }
        player.pause()
        voicePreview.pause()
        options.maskTracks[selectedMaskIndex].updateManualRect(
            rect.scaledAroundCenter(by: factor), at: editingTimeSeconds)
        refreshMaskPreview()
    }

    private func setSelectedMaskStart() {
        guard let selectedMaskIndex else { return }
        let time = editingTimeSeconds
        player.pause()
        options.maskTracks[selectedMaskIndex].activeFromSeconds = time
        if let end = options.maskTracks[selectedMaskIndex].activeUntilSeconds,
            end < time
        {
            options.maskTracks[selectedMaskIndex].activeUntilSeconds = time
        }
        refreshMaskPreview()
    }

    private func setSelectedMaskEnd() {
        guard let selectedMaskIndex else { return }
        let time = editingTimeSeconds
        player.pause()
        options.maskTracks[selectedMaskIndex].activeUntilSeconds = time
        if let start = options.maskTracks[selectedMaskIndex].activeFromSeconds,
            start > time
        {
            options.maskTracks[selectedMaskIndex].activeFromSeconds = time
        }
        refreshMaskPreview()
    }

    private func showSelectedMaskForWholeTimeline() {
        guard let selectedMaskIndex else { return }
        options.maskTracks[selectedMaskIndex].activeFromSeconds = nil
        options.maskTracks[selectedMaskIndex].activeUntilSeconds = nil
        refreshMaskPreview()
    }

    private func requestDeleteMask(id: MaskTrack.ID) {
        pendingDestructiveAction = .mask(id)
    }

    private func deleteMask(id: MaskTrack.ID) {
        guard let removedIndex = options.maskTracks.firstIndex(where: { $0.id == id }) else {
            return
        }
        options.maskTracks.remove(at: removedIndex)
        faceTrackingTasks[id]?.cancel()
        faceTrackingTasks[id] = nil
        if selectedMaskTrackID == id {
            guard !options.maskTracks.isEmpty else {
                selectedMaskTrackID = nil
                refreshMaskPreview()
                return
            }
            let nextIndex = min(removedIndex, options.maskTracks.count - 1)
            selectedMaskTrackID = options.maskTracks[nextIndex].id
        }
        refreshMaskPreview()
    }

    private var destructiveConfirmationTitle: String {
        switch pendingDestructiveAction {
        case .keyframe:
            localization.t("editor.confirmDeletePositionTitle")
        case .mask:
            localization.t("editor.confirmDeleteMaskTitle")
        case nil:
            ""
        }
    }

    private var destructiveConfirmationMessage: String {
        switch pendingDestructiveAction {
        case .keyframe:
            localization.t("editor.confirmDeletePositionMessage")
        case .mask:
            localization.t("editor.confirmDeleteMaskMessage")
        case nil:
            ""
        }
    }

    private func performPendingDestructiveAction() {
        guard let action = pendingDestructiveAction else { return }
        pendingDestructiveAction = nil
        switch action {
        case .keyframe:
            deleteCurrentKeyframe()
        case .mask(let id):
            deleteMask(id: id)
        }
    }

    private func refreshMaskPreview() {
        if options.maskTracks != committedMasks.tracks {
            maskHistory.append(committedMasks)
            if maskHistory.count > 40 { maskHistory.removeFirst() }
            committedMasks = MaskEditSnapshot(tracks: options.maskTracks, selection: selectedMaskTrackID)
        }
        maskPreviewRevision += 1
    }

    private func undoMaskEdit() {
        guard let previous = maskHistory.popLast() else { return }
        options.maskTracks = previous.tracks
        selectedMaskTrackID = previous.selection
        committedMasks = previous
        maskPreviewRevision += 1
        editFeedback = nil
    }

    private func setPositionMode(_ moving: Bool) {
        guard let selectedMaskIndex else { return }
        options.maskTracks[selectedMaskIndex].setPositionMode(
            moving ? .animated : .fixed, at: editingTimeSeconds)
        refreshMaskPreview()
    }

    private func jumpToRecord(forward: Bool) {
        guard let selectedMaskIndex else { return }
        let times = options.maskTracks[selectedMaskIndex].keyframes.map(\.timeSeconds).sorted()
        let time = editingTimeSeconds
        guard
            let target = forward
                ? times.first(where: { $0 > time + 0.12 }) : times.last(where: { $0 < time - 0.12 })
        else { return }
        player.pause()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
            toleranceAfter: .zero)
    }

    private func finishMaskEditing() {
        if let selectedMaskIndex {
            options.maskTracks[selectedMaskIndex].markManualCorrection(
                at: editingTimeSeconds
            )
        }
        refreshMaskPreview()
        if let selectedMaskIndex,
            options.maskTracks[selectedMaskIndex].effectivePositionMode == .animated
        {
            editFeedback = localization.format(
                "editor.positionSaved", formatTimestamp(editingTimeSeconds))
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let total = Int(safeSeconds.rounded(.down))
        return String(format: "%d:%04.1f", total / 60, safeSeconds.truncatingRemainder(dividingBy: 60))
    }

    @MainActor
    private func loadSourceMetadata() async {
        guard sourceMetadata == nil,
            let metadata = try? await SourceVideoMetadata.load(from: videoURL)
        else {
            return
        }
        sourceDuration = (try? await AVURLAsset(url: videoURL).load(.duration).seconds) ?? 0
        sourceMetadata = metadata
        if !metadata.availableResolutions.contains(options.exportResolution) {
            options.exportResolution = .defaultValue(for: metadata.shortEdge)
        }
        if !metadata.availableFrameRates.contains(options.exportFrameRate) {
            options.exportFrameRate = metadata.defaultFrameRate
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

    @MainActor
    private func applyPreview() async {
        previewGeneration += 1
        let generation = previewGeneration
        let wasPlaying = player.rate > 0
        let time = player.currentTime()
        let asset = AVURLAsset(url: videoURL)
        var seedOptions = options
        let syncProcessor = FrameEffectProcessor(options: seedOptions)
        await syncProcessor.warmUp()
        guard generation == previewGeneration, !Task.isCancelled else { return }
        if let synced = await syncMaskEntities(
            using: syncProcessor,
            asset: asset,
            at: time
        ) {
            seedOptions.maskEntities = synced
            options.maskEntities = synced
            if let selectedEntityID,
               !synced.contains(where: { $0.id == selectedEntityID }) {
                self.selectedEntityID = nil
            }
        }
        guard generation == previewGeneration, !Task.isCancelled else { return }

        let processor = FrameEffectProcessor(options: seedOptions)
        await processor.warmUp()
        guard generation == previewGeneration, !Task.isCancelled else { return }

        let composition = AVVideoComposition(asset: asset) { request in
            request.finish(
                with: processor.render(
                    request.sourceImage,
                    at: request.compositionTime
                ),
                context: nil
            )
        }
        guard generation == previewGeneration, !Task.isCancelled else { return }

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        player.replaceCurrentItem(with: item)
        installPlayerObservers()
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        applyAudioMode()
        if wasPlaying {
            player.play()
        }
    }

    @MainActor
    private func syncMaskEntities(
        using processor: FrameEffectProcessor,
        asset: AVURLAsset,
        at time: CMTime
    ) async -> [MaskEntity]? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        do {
            let cgImage = try await generator.image(at: time).image
            return await Task.detached(priority: .userInitiated) {
                processor.syncEntities(from: CIImage(cgImage: cgImage))
            }.value
        } catch {
            return nil
        }
    }

    private func applyAudioMode() {
        MediaPlaybackSession.activate()
        switch options.audio {
        case .original:
            player.isMuted = false
            voicePreview.stop(unload: true)
        case .mute:
            player.isMuted = true
            voicePreview.stop(unload: true)
        case .voice:
            player.isMuted = true
            voicePreview.configure(sourceURL: videoURL, semitones: options.voicePitch)
            Task {
                guard await voicePreview.prepare() else { return }
                let currentTime = player.currentTime().seconds
                let seconds = currentTime.isFinite ? currentTime : 0
                await voicePreview.sync(at: seconds, playing: player.timeControlStatus == .playing)
            }
        }
    }

    private func installPlayerObservers() {
        removePlayerObservers()
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            Task { @MainActor in
                syncVoicePreview(with: player)
            }
        }
        jumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            Task { @MainActor in
                syncVoicePreview(with: player)
            }
        }
    }

    private func removePlayerObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let jumpObserver {
            NotificationCenter.default.removeObserver(jumpObserver)
            self.jumpObserver = nil
        }
    }

    private func syncVoicePreview(with player: AVPlayer) {
        guard options.audio == .voice else { return }
        let seconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        switch player.timeControlStatus {
        case .playing:
            Task { await voicePreview.sync(at: seconds, playing: true) }
        case .paused:
            voicePreview.pause()
        default:
            break
        }
    }
}

private struct ExportSettingsSheet: View {
    @Binding var options: ProcessingOptions
    let metadata: SourceVideoMetadata?
    let sourceDuration: Double
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if let metadata {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text(
                                "\(Int(min(sourceDuration, entitlements.access.maximumDurationSeconds ?? sourceDuration))) s · \(options.exportResolution.title) · \(options.audioMeta(bundle: localization.bundle))"
                            )
                            .font(.headline)
                            if let limit = entitlements.access.maximumDurationSeconds, sourceDuration > limit {
                                Text(localization.t("editor.truncated"))
                                    .font(.footnote)
                            }
                            accessCard
                            if options.scope != .full {
                                exportChoice(
                                    title: localization.t("export.quality"),
                                    hint: options.quality.detail(localization.bundle),
                                    values: QualityMode.allCases,
                                    selection: $options.quality
                                ) { $0.title(localization.bundle) }
                            }
                            exportChoice(
                                title: localization.t("export.resolution"),
                                hint: localization.t("export.resolutionHint"),
                                values: entitlements.access.allowedResolutions(
                                    from: metadata.availableResolutions
                                ),
                                selection: $options.exportResolution,
                                label: \.title
                            )
                            exportChoice(
                                title: localization.t("export.frameRate"),
                                hint: localization.t("export.frameRateHint"),
                                values: metadata.availableFrameRates,
                                selection: $options.exportFrameRate
                            ) { "\($0) fps" }

                            Label(
                                localization.t("export.speedHint"),
                                systemImage: "hare.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(AppPalette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                } else {
                    ProgressView(localization.t("export.reading"))
                }
            }
            .navigationTitle(localization.t("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("export.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(exportButtonTitle) {
                        onExport()
                    }
                    .disabled(metadata == nil || !entitlements.isReady)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: entitlements.isUnlocked) { _, _ in
            enforceAllowedResolution()
        }
        .onAppear {
            enforceAllowedResolution()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(localization)
                .environmentObject(entitlements)
        }
    }

    private var exportButtonTitle: String {
        localization.t("export.start")
    }

    private var accessCard: some View {
        PurchaseStatusCard {
            showPaywall = true
        }
    }

    private func enforceAllowedResolution() {
        guard let metadata else { return }
        let allowed = entitlements.access.allowedResolutions(
            from: metadata.availableResolutions
        )
        if !allowed.contains(options.exportResolution), let fallback = allowed.last {
            options.exportResolution = fallback
        }
    }

    private func exportChoice<Value: Hashable>(
        title: String,
        hint: String,
        values: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value))
                        .lineLimit(1)
                        .tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ASCIIColorSwatch: View {
    let pair: ASCIIColorPair
    let isSelected: Bool
    let accessibilityLabel: String
    var selectionColor: Color = AppPalette.accent.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        Color(
                            .sRGB,
                            red: pair.background.r,
                            green: pair.background.g,
                            blue: pair.background.b,
                            opacity: pair.background.a
                        )
                    )
                Circle()
                    .fill(
                        Color(
                            .sRGB,
                            red: pair.foreground.r,
                            green: pair.foreground.g,
                            blue: pair.foreground.b,
                            opacity: pair.foreground.a
                        )
                    )
                    .padding(7)
            }
            .frame(width: 28, height: 28)
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected ? selectionColor : AppPalette.divider,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum VideoEditorTool: String, CaseIterable, Identifiable {
    case subjects, style, audio, manual
    var id: String { rawValue }
    var titleKey: String.LocalizationValue {
        switch self {
        case .subjects: "editor.subjects"
        case .style: "editor.style"
        case .audio: "editor.audio"
        case .manual: "editor.manualTool"
        }
    }
    var icon: String {
        switch self {
        case .subjects: "person.crop.rectangle"
        case .style: "circle.lefthalf.filled"
        case .audio: "speaker.wave.2"
        case .manual: "square.dashed"
        }
    }
}

private struct MaskEditSnapshot {
    var tracks: [MaskTrack]
    var selection: MaskTrack.ID?
}
