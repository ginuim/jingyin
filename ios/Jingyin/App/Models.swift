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
