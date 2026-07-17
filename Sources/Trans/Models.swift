import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case translate = "翻译"
    case ocr = "OCR"
    case history = "历史"
    case services = "服务"
    case plugins = "插件"
    case settings = "设置"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .translate: "character.book.closed"
        case .ocr: "viewfinder"
        case .history: "clock.arrow.circlepath"
        case .services: "square.stack.3d.up"
        case .plugins: "puzzlepiece.extension"
        case .settings: "gearshape"
        }
    }
}

enum Language: String, CaseIterable, Codable, Identifiable {
    case auto = "自动检测"
    case zhHans = "简体中文"
    case zhHant = "繁体中文"
    case english = "英语"
    case japanese = "日语"
    case korean = "韩语"
    case french = "法语"
    case german = "德语"
    case spanish = "西班牙语"
    case portuguese = "葡萄牙语"
    case russian = "俄语"
    case italian = "意大利语"
    case arabic = "阿拉伯语"
    case thai = "泰语"
    case vietnamese = "越南语"

    var id: String { rawValue }
    var code: String {
        switch self {
        case .auto: "auto"
        case .zhHans: "zh-CN"
        case .zhHant: "zh-TW"
        case .english: "en"
        case .japanese: "ja"
        case .korean: "ko"
        case .french: "fr"
        case .german: "de"
        case .spanish: "es"
        case .portuguese: "pt"
        case .russian: "ru"
        case .italian: "it"
        case .arabic: "ar"
        case .thai: "th"
        case .vietnamese: "vi"
        }
    }

    static func from(code: String) -> Language? {
        let normalized = code.lowercased()
        return allCases.first {
            normalized == $0.code.lowercased() || normalized.hasPrefix($0.code.lowercased() + "-")
        }
    }
}

enum ServiceKind: String, Codable, CaseIterable {
    case appleLocal = "Apple 本地翻译"
    case google = "Google 翻译"
    case microsoft = "Microsoft 翻译"
    case baidu = "百度翻译"
    case youdao = "有道翻译"
    case caiyun = "彩云小译"
    case niu = "小牛翻译"
    case libre = "LibreTranslate"
    case deepL = "DeepL"
    case openAI = "OpenAI 兼容"
    case qwen = "通义千问"
    case deepseek = "DeepSeek"
    case kimi = "Kimi"
    case glm = "智谱 GLM"
    case plugin = "插件"

    /// 使用 OpenAI Chat Completions 协议的大模型服务。
    var usesOpenAIProtocol: Bool {
        switch self {
        case .openAI, .qwen, .deepseek, .kimi, .glm: true
        default: false
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .qwen: "qwen-plus"
        case .deepseek: "deepseek-chat"
        case .kimi: "kimi-latest"
        case .glm: "glm-4-flash"
        default: ""
        }
    }
}

struct TranslationServiceConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: ServiceKind
    var endpoint: String
    var apiKey: String
    var model: String
    var enabled: Bool
    var secretKey: String? = nil
    var region: String? = nil

    static let defaults: [TranslationServiceConfig] = [
        .init(
            name: "Apple 本地翻译",
            kind: .appleLocal,
            endpoint: "local://apple-translation",
            apiKey: "",
            model: "",
            enabled: false
        ),
        .init(
            name: "Google 翻译",
            kind: .google,
            endpoint: "https://translate.googleapis.com/translate_a/single",
            apiKey: "",
            model: "",
            enabled: true
        ),
        .init(
            name: "Microsoft 翻译",
            kind: .microsoft,
            endpoint: "https://api-edge.cognitive.microsofttranslator.com/translate",
            apiKey: "",
            model: "",
            enabled: true
        ),
        .init(
            name: "百度翻译",
            kind: .baidu,
            endpoint: "https://fanyi-api.baidu.com/api/trans/vip/translate",
            apiKey: "",
            model: "",
            enabled: false
        ),
        .init(
            name: "有道翻译",
            kind: .youdao,
            endpoint: "https://openapi.youdao.com/api",
            apiKey: "",
            model: "",
            enabled: false
        ),
        .init(
            name: "彩云小译",
            kind: .caiyun,
            endpoint: "https://api.interpreter.caiyunai.com/v1/translator",
            apiKey: "",
            model: "",
            enabled: false
        ),
        .init(
            name: "小牛翻译",
            kind: .niu,
            endpoint: "https://api.niutrans.com/NiuTransServer/translation",
            apiKey: "",
            model: "",
            enabled: false
        ),
        .init(
            name: "LibreTranslate",
            kind: .libre,
            endpoint: "https://libretranslate.com/translate",
            apiKey: "",
            model: "",
            enabled: true
        ),
        .init(
            name: "DeepL",
            kind: .deepL,
            endpoint: "https://api-free.deepl.com/v2/translate",
            apiKey: "",
            model: "",
            enabled: false
        ),
        .init(
            name: "OpenAI",
            kind: .openAI,
            endpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "",
            model: ServiceKind.openAI.defaultModel,
            enabled: false
        ),
        .init(
            name: "通义千问",
            kind: .qwen,
            endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            apiKey: "",
            model: ServiceKind.qwen.defaultModel,
            enabled: false
        ),
        .init(
            name: "DeepSeek",
            kind: .deepseek,
            endpoint: "https://api.deepseek.com/chat/completions",
            apiKey: "",
            model: ServiceKind.deepseek.defaultModel,
            enabled: false
        ),
        .init(
            name: "Kimi",
            kind: .kimi,
            endpoint: "https://api.moonshot.cn/v1/chat/completions",
            apiKey: "",
            model: ServiceKind.kimi.defaultModel,
            enabled: false
        ),
        .init(
            name: "智谱 GLM",
            kind: .glm,
            endpoint: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            apiKey: "",
            model: ServiceKind.glm.defaultModel,
            enabled: false
        )
    ]

    static func preset(for kind: ServiceKind) -> TranslationServiceConfig {
        if let preset = defaults.first(where: { $0.kind == kind }) {
            var copy = preset
            copy.id = UUID()
            return copy
        }
        switch kind {
        case .plugin:
            return .init(name: "插件", kind: .plugin, endpoint: "", apiKey: "", model: "", enabled: false)
        default:
            return .init(name: kind.rawValue, kind: kind, endpoint: "", apiKey: "", model: "", enabled: false)
        }
    }
}

struct TranslationOutput: Identifiable, Codable, Hashable {
    var id = UUID()
    var serviceID: UUID
    var serviceName: String
    var text: String
    var detectedLanguage: String?
    var duration: TimeInterval
    var error: String?
}

struct HistoryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var sourceText: String
    var sourceLanguage: Language
    var targetLanguage: Language
    var outputs: [TranslationOutput]
    var createdAt = Date()
    var isFavorite = false
    var mode: String = "输入翻译"
}

struct OCRBlock: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var confidence: Float
}

struct PluginManifest: Codable {
    var identifier: String
    var name: String
    var version: String
    var author: String?
    var description: String?
    var main: String?
}

struct InstalledPlugin: Identifiable, Codable, Hashable {
    var id: String { identifier }
    var identifier: String
    var name: String
    var version: String
    var path: String
    var enabled: Bool
    var author: String?
    var summary: String?
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin = false
    var keepOnTop = true
    var autoTranslate = false
    var copyAfterOCR = true
    var smartParagraphs = true
    var rememberWindow = true
    var selectionPopupEnabled = true
    var selectionHotKey = "⌥S"
    var screenshotHotKey = "⌥D"
    var inputHotKey = "⌥A"
    var ocrHotKey = "⌥F"
    var inputBoxHotKey = "⌥T"
    var interfaceLanguage = "简体中文"

    init() {}

    // Older settings.json files lack newly added keys; decode field-by-field so
    // missing keys fall back to defaults instead of discarding the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        keepOnTop = try container.decodeIfPresent(Bool.self, forKey: .keepOnTop) ?? defaults.keepOnTop
        autoTranslate = try container.decodeIfPresent(Bool.self, forKey: .autoTranslate) ?? defaults.autoTranslate
        copyAfterOCR = try container.decodeIfPresent(Bool.self, forKey: .copyAfterOCR) ?? defaults.copyAfterOCR
        smartParagraphs = try container.decodeIfPresent(Bool.self, forKey: .smartParagraphs) ?? defaults.smartParagraphs
        rememberWindow = try container.decodeIfPresent(Bool.self, forKey: .rememberWindow) ?? defaults.rememberWindow
        selectionPopupEnabled = try container.decodeIfPresent(Bool.self, forKey: .selectionPopupEnabled) ?? defaults.selectionPopupEnabled
        selectionHotKey = try container.decodeIfPresent(String.self, forKey: .selectionHotKey) ?? defaults.selectionHotKey
        screenshotHotKey = try container.decodeIfPresent(String.self, forKey: .screenshotHotKey) ?? defaults.screenshotHotKey
        inputHotKey = try container.decodeIfPresent(String.self, forKey: .inputHotKey) ?? defaults.inputHotKey
        ocrHotKey = try container.decodeIfPresent(String.self, forKey: .ocrHotKey) ?? defaults.ocrHotKey
        inputBoxHotKey = try container.decodeIfPresent(String.self, forKey: .inputBoxHotKey) ?? defaults.inputBoxHotKey
        interfaceLanguage = try container.decodeIfPresent(String.self, forKey: .interfaceLanguage) ?? defaults.interfaceLanguage
    }
}

enum TransError: LocalizedError {
    case invalidEndpoint
    case noEnabledService
    case emptyText
    case invalidResponse
    case service(String)
    case imageUnavailable
    case permission(String)
    case plugin(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "服务地址无效"
        case .noEnabledService: "请先启用并配置至少一个翻译服务"
        case .emptyText: "请输入要处理的文本"
        case .invalidResponse: "服务返回了无法识别的数据"
        case .service(let message): message
        case .imageUnavailable: "未找到可识别的图片"
        case .permission(let message): message
        case .plugin(let message): message
        }
    }
}
