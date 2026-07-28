import Foundation

enum QualityMode: String, CaseIterable, Identifiable {
    case fast = "快速"
    case balanced = "均衡"
    case precise = "精细"

    var id: Self { self }
    var frameInterval: Int {
        switch self {
        case .fast: 6
        case .balanced: 3
        case .precise: 1
        }
    }
}

enum MaskScope: String, CaseIterable, Identifiable {
    case subjects = "遮盖主体"
    case background = "遮盖背景"
    case full = "遮盖全画面"

    var id: Self { self }
}

enum EffectStyle: String, CaseIterable, Identifiable {
    case blur = "模糊"
    case pixel = "像素化"
    case ascii = "ASCII"

    var id: Self { self }
}

enum AudioMode: String, CaseIterable, Identifiable {
    case original = "保留原声"
    case mute = "静音"

    var id: Self { self }
}

enum SubjectKind: String, CaseIterable, Identifiable, Hashable {
    case person = "人物"
    case face = "人脸"
    case pet = "宠物"

    var id: Self { self }
    var icon: String {
        switch self {
        case .person: "person.fill"
        case .face: "face.smiling.fill"
        case .pet: "pawprint.fill"
        }
    }
}

struct ProcessingOptions: Equatable {
    var quality: QualityMode = .balanced
    var scope: MaskScope = .subjects
    var style: EffectStyle = .blur
    var audio: AudioMode = .original
    var strength = 32.0
    var subjects: Set<SubjectKind> = [.person]
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

    var title: String {
        switch self {
        case .idle: "等待开始"
        case .reading: "正在读取视频"
        case .loadingModel: "正在加载模型"
        case .warmingUp: "正在预热模型"
        case .analyzing: "正在分析画面"
        case .encoding: "正在编码导出"
        case .completed: "处理完成"
        case .failed: "处理失败"
        }
    }
}
