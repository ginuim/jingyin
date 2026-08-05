import AVFoundation
import Foundation

enum ProductLimits {
    static let maximumInputDurationSeconds: TimeInterval = 5 * 60
    static let maximumInputFileSizeBytes = 1_000_000_000
    static let maximumPhotoBatchCount = 20
}

enum QualityMode: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case precise

    var id: Self { self }

    var frameInterval: Int {
        switch self {
        case .fast: 6
        case .balanced: 3
        case .precise: 1
        }
    }

    func title(_ bundle: Bundle) -> String {
        switch self {
        case .fast: String(localized: "quality.fast", bundle: bundle)
        case .balanced: String(localized: "quality.balanced", bundle: bundle)
        case .precise: String(localized: "quality.precise", bundle: bundle)
        }
    }

    func detail(_ bundle: Bundle) -> String {
        switch self {
        case .fast: String(localized: "quality.detail.fast", bundle: bundle)
        case .balanced: String(localized: "quality.detail.balanced", bundle: bundle)
        case .precise: String(localized: "quality.detail.precise", bundle: bundle)
        }
    }
}

enum ExportResolution: Int, CaseIterable, Identifiable {
    case p480 = 480
    case p720 = 720
    case p1080 = 1080
    case p1440 = 1440
    case p2160 = 2160

    var id: Self { self }

    var title: String {
        switch self {
        case .p480: "480p"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "2K"
        case .p2160: "4K"
        }
    }

    var exportPreset: String {
        // The fixed WxH presets use a landscape bounding box and can silently
        // shrink tall portrait videos below the selected short-edge resolution.
        // The mutable composition already supplies the exact target size.
        AVAssetExportPresetHighestQuality
    }

    static func available(for sourceShortEdge: CGFloat) -> [Self] {
        let supported = allCases.filter {
            CGFloat($0.rawValue) <= sourceShortEdge + 2
        }
        // AVFoundation never upscales with the chosen presets. Keeping one
        // option also lets unusually small clips continue through the UI.
        return supported.isEmpty ? [.p480] : supported
    }

    static func defaultValue(for sourceShortEdge: CGFloat) -> Self {
        available(for: sourceShortEdge)
            .last(where: { $0.rawValue <= 1080 })
            ?? .p480
    }
}

enum ExportAccess: Equatable, Sendable {
    case free
    case lifetime

    static let freeDurationSeconds = 30.0

    var maximumDurationSeconds: TimeInterval? {
        switch self {
        case .free: Self.freeDurationSeconds
        case .lifetime: nil
        }
    }

    func allowedResolutions(
        from resolutions: [ExportResolution]
    ) -> [ExportResolution] {
        switch self {
        case .free:
            let allowed = resolutions.filter { $0.rawValue <= ExportResolution.p720.rawValue }
            return allowed.isEmpty ? [.p480] : allowed
        case .lifetime:
            return resolutions
        }
    }

    func enforce(on options: ProcessingOptions) -> ProcessingOptions {
        guard self == .free else { return options }
        var result = options
        if result.exportResolution.rawValue > ExportResolution.p720.rawValue {
            result.exportResolution = .p720
        }
        return result
    }
}

struct SourceVideoMetadata: Equatable {
    static let commonFrameRates = [24, 30, 50, 60, 90, 120]

    let displaySize: CGSize
    let frameRate: Double

    var shortEdge: CGFloat {
        min(displaySize.width, displaySize.height)
    }

    var availableResolutions: [ExportResolution] {
        ExportResolution.available(for: shortEdge)
    }

    var availableFrameRates: [Int] {
        let sourceRate = max(1, Int(frameRate.rounded()))
        let standard = Self.commonFrameRates.filter { $0 <= sourceRate }
        if standard.contains(sourceRate) {
            return standard
        }
        return Array(Set(standard + [sourceRate])).sorted()
    }

    var defaultFrameRate: Int {
        availableFrameRates.last(where: { $0 <= 30 })
            ?? availableFrameRates.first
            ?? 24
    }

    static func load(from url: URL) async throws -> Self {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let displaySize = VideoCoordinateSpace.displaySize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let loadedFrameRate = Double(nominalFrameRate)
        return Self(
            displaySize: displaySize,
            frameRate: loadedFrameRate.isFinite && loadedFrameRate > 0
                ? loadedFrameRate
                : 30
        )
    }
}

enum MaskScope: String, CaseIterable, Identifiable {
    case subjects
    case background
    case full

    var id: Self { self }

    func title(_ bundle: Bundle) -> String {
        switch self {
        case .subjects: String(localized: "scope.subjects", bundle: bundle)
        case .background: String(localized: "scope.background", bundle: bundle)
        case .full: String(localized: "scope.full", bundle: bundle)
        }
    }
}

enum EffectStyle: String, CaseIterable, Identifiable {
    case blur
    case pixel
    case ascii
    case sticker

    var id: Self { self }

    func title(_ bundle: Bundle) -> String {
        switch self {
        case .blur: String(localized: "style.blur", bundle: bundle)
        case .pixel: String(localized: "style.pixel", bundle: bundle)
        case .ascii: String(localized: "style.ascii", bundle: bundle)
        case .sticker: String(localized: "style.sticker", bundle: bundle)
        }
    }
}

enum StickerEmoji: String, CaseIterable, Identifiable, Sendable {
    case sunglasses = "😎"
    case disguise = "🥸"
    case clown = "🤡"
    case alien = "👽"
    case ghost = "👻"
    case robot = "🤖"
    case monkey = "🙈"
    case cat = "😺"
    case heartEyes = "😍"
    case starStruck = "🤩"
    case cowboy = "🤠"
    case party = "🥳"
    case smilingDevil = "😈"
    case pumpkin = "🎃"
    case panda = "🐼"
    case frog = "🐸"
    case smile = "😊"
    case wink = "😉"
    case laughing = "😂"
    case thinking = "🤔"
    case shushing = "🤫"
    case zipperMouth = "🤐"
    case mindBlown = "🤯"
    case scream = "😱"
    case angry = "😡"
    case skull = "💀"
    case poop = "💩"
    case dog = "🐶"
    case fox = "🦊"
    case tiger = "🐯"
    case lion = "🦁"
    case bear = "🐻"

    var id: String { rawValue }
}

enum AudioMode: String, CaseIterable, Identifiable {
    case original
    case voice
    case mute

    var id: Self { self }

    func title(_ bundle: Bundle) -> String {
        switch self {
        case .original: String(localized: "audio.original", bundle: bundle)
        case .voice: String(localized: "audio.voice", bundle: bundle)
        case .mute: String(localized: "audio.mute", bundle: bundle)
        }
    }

    func meta(_ bundle: Bundle) -> String {
        switch self {
        case .original: String(localized: "audio.meta.original", bundle: bundle)
        case .voice: String(localized: "audio.meta.voice", bundle: bundle)
        case .mute: String(localized: "audio.meta.mute", bundle: bundle)
        }
    }
}

enum SubjectKind: String, CaseIterable, Identifiable, Hashable {
    case person
    case face
    case pet

    var id: Self { self }

    var icon: String {
        switch self {
        case .person: "person.fill"
        case .face: "face.smiling.fill"
        case .pet: "pawprint.fill"
        }
    }

    func title(_ bundle: Bundle) -> String {
        switch self {
        case .person: String(localized: "subject.person", bundle: bundle)
        case .face: String(localized: "subject.face", bundle: bundle)
        case .pet: String(localized: "subject.pet", bundle: bundle)
        }
    }
}

enum VoicePitchStore {
    static let key = "jingyin.voicePitch"
    static let `default` = -4
    static let range = -8...8

    static func load() -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else { return `default` }
        return clamp(UserDefaults.standard.integer(forKey: key))
    }

    static func save(_ value: Int) {
        UserDefaults.standard.set(clamp(value), forKey: key)
    }

    static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func metaLabel(_ semitones: Int, bundle: Bundle) -> String {
        let value = clamp(semitones)
        let signed = value > 0 ? "+\(value)" : "\(value)"
        let template = String(localized: "pitch.meta", bundle: bundle)
        let localeId = bundle.preferredLocalizations.first ?? "en"
        return String(format: template, locale: Locale(identifier: localeId), signed)
    }
}

struct EffectRGBA: Equatable, Sendable, Codable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    static let asciiDefaultForeground = EffectRGBA(r: 0.957, g: 0.969, b: 0.961)
    static let asciiDefaultBackground = EffectRGBA(r: 0.02, g: 0.027, b: 0.024)

    func matches(_ other: EffectRGBA, tolerance: Double = 0.002) -> Bool {
        abs(r - other.r) <= tolerance
            && abs(g - other.g) <= tolerance
            && abs(b - other.b) <= tolerance
            && abs(a - other.a) <= tolerance
    }

    /// Same hue family, mixed toward white for ASCII theme backgrounds.
    func lightened(towardWhite amount: Double = 0.72) -> EffectRGBA {
        let t = min(max(amount, 0), 1)
        return EffectRGBA(
            r: r + (1 - r) * t,
            g: g + (1 - g) * t,
            b: b + (1 - b) * t,
            a: a
        )
    }
}

struct ASCIIColorPair: Equatable, Sendable, Codable, Identifiable {
    var foreground: EffectRGBA
    var background: EffectRGBA

    var id: String {
        [
            foreground.r, foreground.g, foreground.b, foreground.a,
            background.r, background.g, background.b, background.a
        ]
        .map { String(format: "%.4f", $0) }
        .joined(separator: ",")
    }

    func matches(_ other: ASCIIColorPair) -> Bool {
        foreground.matches(other.foreground) && background.matches(other.background)
    }
}

struct ASCIIColorTheme: Identifiable, Equatable {
    let id: String
    let foreground: EffectRGBA
    let background: EffectRGBA

    var pair: ASCIIColorPair {
        ASCIIColorPair(foreground: foreground, background: background)
    }

    func title(_ bundle: Bundle) -> String {
        String(localized: String.LocalizationValue("ascii.theme.\(id)"), bundle: bundle)
    }

    static let all: [ASCIIColorTheme] = [
        .init(
            id: "classic",
            foreground: .asciiDefaultBackground,
            background: .asciiDefaultForeground
        ),
        .tinted(id: "amber", color: EffectRGBA(r: 0.82, g: 0.52, b: 0.12)),
        .tinted(id: "blue", color: EffectRGBA(r: 0.28, g: 0.48, b: 0.82)),
        .init(
            id: "paper",
            foreground: EffectRGBA(r: 0.88, g: 0.85, b: 0.78),
            background: EffectRGBA(r: 0.12, g: 0.12, b: 0.11)
        ),
        .tinted(id: "matrix", color: EffectRGBA(r: 0.1, g: 0.55, b: 0.22)),
        .tinted(id: "magenta", color: EffectRGBA(r: 0.78, g: 0.28, b: 0.55)),
    ]

    /// Deep base color as background; lightened tint as glyph.
    private static func tinted(id: String, color: EffectRGBA) -> ASCIIColorTheme {
        .init(
            id: id,
            foreground: color.lightened(towardWhite: 0.72),
            background: color
        )
    }
}

enum ASCIIColorRecentStore {
    static let key = "jingyin.asciiRecentColors"
    static let maxCount = 5

    static func load() -> [ASCIIColorPair] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let pairs = try? JSONDecoder().decode([ASCIIColorPair].self, from: data) else {
            return []
        }
        return Array(pairs.prefix(maxCount))
    }

    static func remember(_ pair: ASCIIColorPair) {
        var pairs = load().filter { !$0.matches(pair) }
        pairs.insert(pair, at: 0)
        if pairs.count > maxCount {
            pairs = Array(pairs.prefix(maxCount))
        }
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// One auto-detected subject that the user can enable/disable independently.
/// Video keeps these in the edit session; masks are regenerated per frame.
struct MaskEntity: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var kind: SubjectKind
    var source: MaskTrackSource
    var isEnabled: Bool
    var lastRect: NormalizedVideoRect

    init(
        id: UUID = UUID(),
        kind: SubjectKind,
        source: MaskTrackSource,
        isEnabled: Bool = true,
        lastRect: NormalizedVideoRect
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.isEnabled = isEnabled
        self.lastRect = lastRect
    }
}

struct ProcessingOptions: Equatable {
    var quality: QualityMode = .balanced
    var scope: MaskScope = .subjects
    var style: EffectStyle = .pixel
    var audio: AudioMode = .original
    var voicePitch: Int = VoicePitchStore.load()
    var strength = 24.0
    var asciiForeground: EffectRGBA = .asciiDefaultForeground
    var asciiBackground: EffectRGBA = .asciiDefaultBackground
    var stickerEmoji: StickerEmoji = .sunglasses
    /// Face rectangles already detected outside `FrameEffectProcessor`, such as
    /// photo batch masks. Each rectangle receives exactly one sticker.
    var stickerFaceRects: [NormalizedVideoRect] = []
    var subjects: Set<SubjectKind> = [.person]
    var maskTracks: [MaskTrack] = []
    /// Auto-detected subjects for per-entity enable/disable (video session).
    var maskEntities: [MaskEntity] = []
    var exportResolution: ExportResolution = .p1080
    var exportFrameRate = 30

    var supportsFaceSticker: Bool {
        // Stickers are a face-subject effect. The mask scope controls where
        // the privacy effect is applied, but should not hide the Emoji tool
        // once the user has explicitly selected faces.
        subjects == [.face]
    }

    mutating func toggleSubject(_ subject: SubjectKind) {
        if subjects.contains(subject) {
            subjects.remove(subject)
            return
        }

        switch subject {
        case .person:
            subjects.remove(.face)
        case .face:
            subjects.remove(.person)
        case .pet:
            break
        }
        subjects.insert(subject)
    }

    func audioMeta(bundle: Bundle) -> String {
        switch audio {
        case .original: AudioMode.original.meta(bundle)
        case .mute: AudioMode.mute.meta(bundle)
        case .voice: VoicePitchStore.metaLabel(voicePitch, bundle: bundle)
        }
    }
}

enum ProcessingOptionsPreferenceStore {
    private static let videoKey = "jingyin.processingOptions.video"
    private static let photoKey = "jingyin.processingOptions.photo"

    static func loadVideo(defaults: UserDefaults = .standard) -> ProcessingOptions {
        var options = ProcessingOptions()
        guard let preferences = load(forKey: videoKey, defaults: defaults) else {
            return options
        }
        preferences.applyCommon(to: &options)
        if let rawValue = preferences.audio,
           let audio = AudioMode(rawValue: rawValue) {
            options.audio = audio
        }
        if let voicePitch = preferences.voicePitch {
            options.voicePitch = VoicePitchStore.clamp(voicePitch)
        }
        if let rawValue = preferences.exportResolution,
           let resolution = ExportResolution(rawValue: rawValue) {
            options.exportResolution = resolution
        }
        if let frameRate = preferences.exportFrameRate,
           (1...240).contains(frameRate) {
            options.exportFrameRate = frameRate
        }
        return options
    }

    static func loadPhoto(defaults: UserDefaults = .standard) -> ProcessingOptions {
        var options = ProcessingOptions()
        options.subjects = [.face]
        guard let preferences = load(forKey: photoKey, defaults: defaults) else {
            return options
        }
        preferences.applyCommon(to: &options)
        return options
    }

    static func saveVideo(
        _ options: ProcessingOptions,
        defaults: UserDefaults = .standard
    ) {
        save(
            StoredPreferences(
                options: options,
                audio: options.audio.rawValue,
                voicePitch: options.voicePitch,
                exportResolution: options.exportResolution.rawValue,
                exportFrameRate: options.exportFrameRate
            ),
            forKey: videoKey,
            defaults: defaults
        )
    }

    static func savePhoto(
        _ options: ProcessingOptions,
        defaults: UserDefaults = .standard
    ) {
        save(StoredPreferences(options: options), forKey: photoKey, defaults: defaults)
    }

    private static func load(
        forKey key: String,
        defaults: UserDefaults
    ) -> StoredPreferences? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoredPreferences.self, from: data)
    }

    private static func save(
        _ preferences: StoredPreferences,
        forKey key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }

    private struct StoredPreferences: Codable {
        var quality: String
        var scope: String
        var style: String
        var strength: Double
        var asciiForeground: EffectRGBA
        var asciiBackground: EffectRGBA
        var stickerEmoji: String
        var subjects: [String]
        var audio: String?
        var voicePitch: Int?
        var exportResolution: Int?
        var exportFrameRate: Int?

        init(
            options: ProcessingOptions,
            audio: String? = nil,
            voicePitch: Int? = nil,
            exportResolution: Int? = nil,
            exportFrameRate: Int? = nil
        ) {
            quality = options.quality.rawValue
            scope = options.scope.rawValue
            style = options.style.rawValue
            strength = options.strength
            asciiForeground = options.asciiForeground
            asciiBackground = options.asciiBackground
            stickerEmoji = options.stickerEmoji.rawValue
            subjects = options.subjects.map(\.rawValue).sorted()
            self.audio = audio
            self.voicePitch = voicePitch
            self.exportResolution = exportResolution
            self.exportFrameRate = exportFrameRate
        }

        func applyCommon(to options: inout ProcessingOptions) {
            if let quality = QualityMode(rawValue: quality) {
                options.quality = quality
            }
            if let scope = MaskScope(rawValue: scope) {
                options.scope = scope
            }
            if let style = EffectStyle(rawValue: style) {
                options.style = style
            }
            if strength.isFinite {
                options.strength = min(max(strength, strengthRange.lowerBound), strengthRange.upperBound)
            }
            options.asciiForeground = asciiForeground.sanitized(
                fallback: .asciiDefaultForeground
            )
            options.asciiBackground = asciiBackground.sanitized(
                fallback: .asciiDefaultBackground
            )
            if let stickerEmoji = StickerEmoji(rawValue: stickerEmoji) {
                options.stickerEmoji = stickerEmoji
            }
            options.subjects = Set(subjects.compactMap(SubjectKind.init(rawValue:)))
            if options.style == .sticker, !options.supportsFaceSticker {
                options.style = .pixel
                options.strength = 24
            }
        }

        private var strengthRange: ClosedRange<Double> {
            switch EffectStyle(rawValue: style) ?? .pixel {
            case .blur: 4...64
            case .pixel: 6...48
            case .ascii: 8...30
            case .sticker: 40...120
            }
        }
    }
}

private extension EffectRGBA {
    func sanitized(fallback: EffectRGBA) -> EffectRGBA {
        let components = [r, g, b, a]
        guard components.allSatisfy(\.isFinite) else { return fallback }
        return EffectRGBA(
            r: min(max(r, 0), 1),
            g: min(max(g, 0), 1),
            b: min(max(b, 0), 1),
            a: min(max(a, 0), 1)
        )
    }
}

enum ProcessingStage: Equatable {
    case idle
    case reading
    case loadingModel
    case warmingUp
    case analyzing
    case encoding
    case completed(URL)
    case failed(String)

    func title(bundle: Bundle) -> String {
        switch self {
        case .idle: String(localized: "stage.idle", bundle: bundle)
        case .reading: String(localized: "stage.reading", bundle: bundle)
        case .loadingModel: String(localized: "stage.loadingModel", bundle: bundle)
        case .warmingUp: String(localized: "stage.warmingUp", bundle: bundle)
        case .analyzing: String(localized: "stage.analyzing", bundle: bundle)
        case .encoding: String(localized: "stage.encoding", bundle: bundle)
        case .completed: String(localized: "stage.completed", bundle: bundle)
        case .failed: String(localized: "stage.failed", bundle: bundle)
        }
    }
}
