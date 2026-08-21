import XCTest
@testable import Trans

final class TranslationClientTests: XCTestCase {
    func testSelectionCaptureAcceptsSuccessfulCopyDespiteStalePermissionPreflight() {
        XCTAssertTrue(SelectionCapturePolicy.accepts(
            preflightTrusted: false,
            pasteboardChanged: true,
            text: "selected text"
        ))
    }

    func testSelectionCaptureRejectsWhenCopyDidNotChangePasteboard() {
        XCTAssertFalse(SelectionCapturePolicy.accepts(
            preflightTrusted: true,
            pasteboardChanged: false,
            text: "stale clipboard text"
        ))
    }

    func testPublicDefaultServicesNeedNoCredentials() {
        let publicServices = TranslationServiceConfig.defaults.filter { [.google, .microsoft].contains($0.kind) }
        XCTAssertEqual(publicServices.count, 2)
        XCTAssertTrue(publicServices.allSatisfy { $0.enabled && $0.apiKey.isEmpty })
    }

    func testAppleLocalServiceIsAvailableWithoutCredentials() {
        let service = TranslationServiceConfig.defaults.first { $0.kind == .appleLocal }
        XCTAssertNotNil(service)
        XCTAssertEqual(service?.endpoint, "local://apple-translation")
        XCTAssertEqual(service?.apiKey, "")
    }

    func testParsesGoogleResponse() throws {
        let data = #"[[["你好","Hello",null,null,1]],null,"en"]"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .google)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.detected, "en")
    }

    func testParsesMicrosoftResponse() throws {
        let data = #"[{"detectedLanguage":{"language":"en","score":1},"translations":[{"text":"你好","to":"zh-Hans"}]}]"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .microsoft)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.detected, "en")
    }

    func testParsesBaiduResponse() throws {
        let data = #"{"from":"en","to":"zh","trans_result":[{"src":"Hello","dst":"你好"}]}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .baidu)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.detected, "en")
    }

    func testParsesYoudaoResponse() throws {
        let data = #"{"errorCode":"0","translation":["你好"],"l":"en2zh-CHS"}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .youdao)
        XCTAssertEqual(result.text, "你好")
    }

    func testParsesCaiyunResponse() throws {
        let data = #"{"target":["你好"],"detected_lang":"en"}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .caiyun)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.detected, "en")
    }

    func testParsesNiuResponse() throws {
        let data = #"{"tgt_text":"你好","to":"zh"}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .niu)
        XCTAssertEqual(result.text, "你好")
    }

    func testServiceSignatureHashes() {
        XCTAssertEqual(Signature.md5("hello"), "5d41402abc4b2a76b9719d911017c592")
        XCTAssertEqual(Signature.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testParsesLibreTranslateResponse() throws {
        let data = #"{"translatedText":"你好","detectedLanguage":{"language":"en","confidence":98}}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .libre)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.detected, "en")
    }

    func testParsesDeepLResponse() throws {
        let data = #"{"translations":[{"detected_source_language":"EN","text":"你好"}]}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .deepL)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.detected, "EN")
    }

    func testParsesOpenAIResponse() throws {
        let data = #"{"choices":[{"message":{"role":"assistant","content":"  你好\n"}}]}"#.data(using: .utf8)!
        let result = try TranslationClient.parse(data: data, kind: .openAI)
        XCTAssertEqual(result.text, "你好")
    }

    func testParsesOpenAICompatibleLLMResponses() throws {
        let data = #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#.data(using: .utf8)!
        for kind in [ServiceKind.ollama, .qwen, .deepseek, .kimi, .glm] {
            let result = try TranslationClient.parse(data: data, kind: kind)
            XCTAssertEqual(result.text, "你好")
        }
    }

    func testOllamaDefaultServicePreset() {
        let service = TranslationServiceConfig.defaults.first { $0.kind == .ollama }
        XCTAssertEqual(service?.endpoint, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertEqual(service?.model, "llama3.2")
        XCTAssertEqual(service?.apiKey, "")
        XCTAssertFalse(service?.enabled ?? true)
        XCTAssertTrue(ServiceKind.ollama.usesOpenAIProtocol)
    }

    func testLLMDefaultServicePresets() {
        for kind in [ServiceKind.qwen, .deepseek, .kimi, .glm] {
            let service = TranslationServiceConfig.defaults.first { $0.kind == kind }
            XCTAssertNotNil(service, "\(kind.rawValue) 缺少默认配置")
            XCTAssertTrue(service?.endpoint.hasPrefix("https://") == true)
            XCTAssertEqual(service?.model.isEmpty, false)
            XCTAssertEqual(service?.enabled, false)
            XCTAssertTrue(kind.usesOpenAIProtocol)
        }
    }

    func testPresetForLLMKindCopiesDefaultEndpointAndModel() {
        let preset = TranslationServiceConfig.preset(for: .deepseek)
        XCTAssertEqual(preset.endpoint, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(preset.model, "deepseek-chat")
        XCTAssertFalse(preset.enabled)
    }

    func testInvalidResponseThrows() {
        XCTAssertThrowsError(try TranslationClient.parse(data: Data("{}".utf8), kind: .deepL))
    }

    func testPersistenceRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersistenceStore(directory: folder)
        var settings = AppSettings()
        settings.autoTranslate = true
        store.save(settings, to: "settings.json")
        XCTAssertEqual(store.load(AppSettings.self, from: "settings.json", fallback: .init()), settings)
    }
}
