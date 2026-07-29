import AVFoundation
import AVKit
import SwiftUI

struct EditorView: View {
    let videoURL: URL
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var player: AVPlayer
    @State private var options = ProcessingOptions()
    @State private var showProcessing = false
    @State private var showExportSettings = false
    @State private var showPaywall = false
    @State private var sourceMetadata: SourceVideoMetadata?
    @State private var previewGeneration = 0
    @State private var maskPreviewRevision = 0
    @State private var playheadSeconds = 0.0
    @State private var selectedMaskTrackID: MaskTrack.ID?
    @State private var showManualMaskEditor = false
    @State private var showFullScreenMaskEditor = false
    @State private var faceDetectionSnapshot: FaceDetectionSnapshot?
    @State private var showFaceSelection = false
    @State private var isDetectingFaces = false
    @State private var faceDetectionMessage: String?
    @State private var faceTrackingTasks: [MaskTrack.ID: Task<Void, Never>] = [:]
    @StateObject private var voicePreview = VoicePreviewEngine()
    @State private var statusObserver: NSKeyValueObservation?
    @State private var jumpObserver: NSObjectProtocol?

    init(videoURL: URL) {
        self.videoURL = videoURL
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ControlledVideoPlayer(
                    player: player,
                    showsCentralPlayButton: !showManualMaskEditor
                        || selectedMaskTrackID == nil,
                    timelineMarkers: manualMaskTimelineMarkers,
                    timelineRanges: manualMaskTimelineRanges,
                    onTimeChanged: { playheadSeconds = $0 },
                    onFullScreen: {
                        showFullScreenMaskEditor = true
                    }
                ) {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            if showManualMaskEditor {
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
                                    onDeleteTrack: deleteMask
                                )
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Label(localization.t("editor.previewBadge"), systemImage: "eye.fill")
                                .font(.caption.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(10)
                        }
                }

                settings

                PurchaseStatusCard {
                    showPaywall = true
                }

                if voicePreview.isPreparing, options.audio == .voice {
                    ProgressView(localization.t("editor.preparingVoice"))
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if voicePreview.isPreviewUnsupported, options.audio == .voice {
                    Label(localization.t("error.previewUnsupported"), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    player.pause()
                    voicePreview.stop(unload: true)
                    showExportSettings = true
                } label: {
                    Label(localization.t("editor.start"), systemImage: "wand.and.stars")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .foregroundStyle(.black)
                .disabled(hasTrackingInProgress)

                if hasTrackingInProgress {
                    Label(
                        localization.t("tracking.waitForCompletion"),
                        systemImage: "hourglass"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.07))
        .navigationTitle(localization.t("editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showProcessing) {
            ProcessingView(
                videoURL: videoURL,
                options: options,
                access: entitlements.access
            )
        }
        .sheet(isPresented: $showExportSettings) {
            ExportSettingsSheet(
                options: $options,
                metadata: sourceMetadata,
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
                isMaskEditingEnabled: showManualMaskEditor,
                canDeleteCurrentKeyframe: canDeleteCurrentKeyframe,
                onAddMask: addManualMask,
                onInsertKeyframe: insertKeyframe,
                onDeleteCurrentKeyframe: deleteCurrentKeyframe,
                onShrinkMask: shrinkSelectedMask,
                onEnlargeMask: enlargeSelectedMask,
                onDeleteTrack: deleteMask,
                onEditingEnded: finishMaskEditing
            )
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
        .onChange(of: showManualMaskEditor) { _, isExpanded in
            if !isExpanded {
                selectedMaskTrackID = nil
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
        }
    }

    /// Exclude audio/pitch so voice slider does not rebuild the mask composition.
    private var videoEffectToken: String {
        let subjects = options.subjects.map(\.rawValue).sorted().joined(separator: ",")
        return "\(options.quality.rawValue)|\(options.scope.rawValue)|\(options.style.rawValue)|\(options.strength)|\(subjects)|\(maskPreviewRevision)"
    }

    private var settings: some View {
        let bundle = localization.bundle
        return VStack(spacing: 18) {
            OptionSection(title: localization.t("editor.scope"), systemImage: "viewfinder") {
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

            if options.scope != .full {
                CollapsibleOptionSection(
                    title: localization.t("editor.manualMasks"),
                    systemImage: "square.dashed",
                    meta: manualMaskCountLabel,
                    isExpanded: $showManualMaskEditor
                ) {
                    HStack(spacing: 10) {
                        Button {
                            addManualMask(shape: .ellipse)
                        } label: {
                            Label(
                                localization.t("editor.addEllipse"),
                                systemImage: "circle.dashed"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            addManualMask(shape: .rectangle)
                        } label: {
                            Label(
                                localization.t("editor.addRectangle"),
                                systemImage: "rectangle.dashed"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !options.maskTracks.isEmpty {
                        maskSelector
                    }

                    if selectedMaskTrackID != nil {
                        HStack(spacing: 10) {
                            Button(action: shrinkSelectedMask) {
                                Label(
                                    localization.t("editor.shrinkMask"),
                                    systemImage: "minus.magnifyingglass"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: enlargeSelectedMask) {
                                Label(
                                    localization.t("editor.enlargeMask"),
                                    systemImage: "plus.magnifyingglass"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 10) {
                            maskVisibilityMenu
                                .frame(maxWidth: .infinity)

                            positionRecordsMenu
                                .frame(maxWidth: .infinity)
                        }

                        if let selectedFaceTrack {
                            faceTrackingStatus(selectedFaceTrack)
                        }
                    }

                    Text(localization.t("editor.manualMaskHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        localization.t("editor.keyframeTimelineHint"),
                        systemImage: "timeline.selection"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                OptionSection(title: localization.t("editor.subjects"), systemImage: "person.2.crop.square.stack") {
                    HStack(spacing: 10) {
                        ForEach(SubjectKind.allCases) { subject in
                            Button {
                                toggle(subject)
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: subject.icon)
                                    Text(subject.title(bundle))
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    options.subjects.contains(subject) ? Color.mint.opacity(0.9) : .white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .foregroundStyle(options.subjects.contains(subject) ? .black : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                OptionSection(title: localization.t("editor.quality"), systemImage: "speedometer") {
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

            OptionSection(title: localization.t("editor.style"), systemImage: "circle.lefthalf.filled") {
                Picker(localization.t("editor.style"), selection: $options.style) {
                    ForEach(EffectStyle.allCases) {
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
            }

            OptionSection(
                title: localization.t("editor.audio"),
                systemImage: "speaker.wave.2",
                meta: options.audioMeta(bundle: bundle)
            ) {
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
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                }

                Text(localization.t("editor.pitchHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle(_ subject: SubjectKind) {
        options.toggleSubject(subject)
    }

    private var manualMaskCountLabel: String? {
        guard !options.maskTracks.isEmpty else { return nil }
        return localization.format(
            "editor.maskCount",
            Int64(options.maskTracks.count)
        )
    }

    private var manualMaskTimelineMarkers: [VideoTimelineMarker] {
        guard showManualMaskEditor else { return [] }
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
        guard showManualMaskEditor else { return [] }
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
                                ? Color.mint
                                : Color.white.opacity(0.08),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedMaskTrackID == track.id ? .black : .white)
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
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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
                action: deleteCurrentKeyframe
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
        .buttonStyle(.bordered)
    }

    private var selectedMaskVisibilitySummary: String {
        guard let selectedMaskIndex else {
            return localization.t("editor.showForEntireVideo")
        }
        let track = options.maskTracks[selectedMaskIndex]
        switch (track.activeFromSeconds, track.activeUntilSeconds) {
        case let (start?, end?):
            return localization.format(
                "editor.visibilityRange",
                formatTimestamp(start),
                formatTimestamp(end)
            )
        case let (start?, nil):
            return localization.format(
                "editor.visibilityFrom",
                formatTimestamp(start)
            )
        case let (nil, end?):
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
                      }) else {
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
                guard let index = options.maskTracks.firstIndex(where: {
                    $0.id == trackID
                }) else {
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
            .foregroundStyle(.mint)
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
                .foregroundStyle(.yellow)
                .fixedSize(horizontal: false, vertical: true)

                Text(localization.t("tracking.correctionHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: retrySelectedFaceTracking) {
                    Label(
                        localization.t("tracking.continue"),
                        systemImage: "scope"
                    )
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .needsRetracking:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    localization.t("tracking.correctionSaved"),
                    systemImage: "diamond.fill"
                )
                .font(.caption)
                .foregroundStyle(.mint)

                Button(action: retrySelectedFaceTracking) {
                    Label(
                        localization.t("tracking.continue"),
                        systemImage: "scope"
                    )
                }
                .buttonStyle(.bordered)
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
                .keyframedRect(at: editingTimeSeconds) else {
            return
        }
        player.pause()
        voicePreview.pause()
        options.maskTracks[selectedMaskIndex].setKeyframe(
            MaskKeyframe(timeSeconds: editingTimeSeconds, rect: rect)
        )
        refreshMaskPreview()
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
                .keyframedRect(at: editingTimeSeconds) else {
            return
        }
        player.pause()
        voicePreview.pause()
        options.maskTracks[selectedMaskIndex].setKeyframe(
            MaskKeyframe(
                timeSeconds: editingTimeSeconds,
                rect: rect.scaledAroundCenter(by: factor)
            )
        )
        refreshMaskPreview()
    }

    private func setSelectedMaskStart() {
        guard let selectedMaskIndex else { return }
        let time = editingTimeSeconds
        player.pause()
        options.maskTracks[selectedMaskIndex].activeFromSeconds = time
        if let end = options.maskTracks[selectedMaskIndex].activeUntilSeconds,
           end < time {
            options.maskTracks[selectedMaskIndex].activeUntilSeconds = time
        }
        insertKeyframe()
    }

    private func setSelectedMaskEnd() {
        guard let selectedMaskIndex else { return }
        let time = editingTimeSeconds
        player.pause()
        options.maskTracks[selectedMaskIndex].activeUntilSeconds = time
        if let start = options.maskTracks[selectedMaskIndex].activeFromSeconds,
           start > time {
            options.maskTracks[selectedMaskIndex].activeFromSeconds = time
        }
        insertKeyframe()
    }

    private func showSelectedMaskForWholeTimeline() {
        guard let selectedMaskIndex else { return }
        options.maskTracks[selectedMaskIndex].activeFromSeconds = nil
        options.maskTracks[selectedMaskIndex].activeUntilSeconds = nil
        refreshMaskPreview()
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

    private func refreshMaskPreview() {
        maskPreviewRevision += 1
    }

    private func finishMaskEditing() {
        if let selectedMaskIndex {
            options.maskTracks[selectedMaskIndex].markManualCorrection(
                at: editingTimeSeconds
            )
        }
        refreshMaskPreview()
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let total = Int(safeSeconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @MainActor
    private func loadSourceMetadata() async {
        guard sourceMetadata == nil,
              let metadata = try? await SourceVideoMetadata.load(from: videoURL) else {
            return
        }
        sourceMetadata = metadata
        options.exportResolution = .defaultValue(for: metadata.shortEdge)
        options.exportFrameRate = metadata.defaultFrameRate
    }

    private var strengthRange: ClosedRange<Double> {
        switch options.style {
        case .blur: 4...64
        case .pixel: 6...48
        case .ascii: 8...30
        }
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
        }
    }

    @MainActor
    private func applyPreview() async {
        previewGeneration += 1
        let generation = previewGeneration
        let wasPlaying = player.rate > 0
        let time = player.currentTime()
        let asset = AVURLAsset(url: videoURL)
        let processor = FrameEffectProcessor(options: options)
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

    private func applyAudioMode() {
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
                            accessCard
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
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
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
        entitlements.isUnlocked
            ? localization.t("export.start")
            : localization.t("export.startFree")
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        Text(label(value))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                selection.wrappedValue == value
                                    ? Color.mint
                                    : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(
                                selection.wrappedValue == value ? .black : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct OptionSection<Content: View>: View {
    let title: String
    let systemImage: String
    var meta: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if let meta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct CollapsibleOptionSection<Content: View>: View {
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
