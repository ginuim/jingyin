import AVFoundation
import Foundation

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
        let transformed = naturalSize.applying(preferredTransform)
        let displaySize = CGSize(
            width: abs(transformed.width),
            height: abs(transformed.height)
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

    var id: Self { self }

    func title(_ bundle: Bundle) -> String {
        switch self {
        case .blur: String(localized: "style.blur", bundle: bundle)
        case .pixel: String(localized: "style.pixel", bundle: bundle)
        case .ascii: String(localized: "style.ascii", bundle: bundle)
        }
    }
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

struct ProcessingOptions: Equatable {
    var quality: QualityMode = .balanced
    var scope: MaskScope = .subjects
    var style: EffectStyle = .blur
    var audio: AudioMode = .original
    var voicePitch: Int = VoicePitchStore.load()
    var strength = 32.0
    var subjects: Set<SubjectKind> = [.person]
    var exportResolution: ExportResolution = .p1080
    var exportFrameRate = 30

    func audioMeta(bundle: Bundle) -> String {
        switch audio {
        case .original: AudioMode.original.meta(bundle)
        case .mute: AudioMode.mute.meta(bundle)
        case .voice: VoicePitchStore.metaLabel(voicePitch, bundle: bundle)
        }
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
