import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .translate
    @Published var sourceText = ""
    @Published var sourceLanguage: Language = .auto
    @Published var targetLanguage: Language = .zhHans
    @Published var outputs: [TranslationOutput] = []
    @Published var isTranslating = false
    @Published var statusMessage: String?

    @Published var ocrImage: NSImage?
    @Published var ocrText = ""
    @Published var ocrBlocks: [OCRBlock] = []
    @Published var qrCodes: [String] = []
    @Published var isRecognizing = false
    @Published var continuousOCR = false

    @Published var history: [HistoryItem]
    @Published var services: [TranslationServiceConfig]
    @Published var plugins: [InstalledPlugin]
    @Published var settings: AppSettings
    @Published var permissionTestResult: String?
    @Published var serviceValidation: [UUID: String] = [:]
    @Published var hotKeyWarning: String?

    let captureService = CaptureService()
    let speechService = SpeechService()
    private let translationClient = TranslationClient()
    private let ocrService = OCRService()
    private let persistence: PersistenceStore
    private let pluginManager: PluginManager
    private let credentialStore: CredentialStore
    private let hotKeys = HotKeyService()
    let selectionPopup = SelectionPopupController()
    private let selectionWatcher = SelectionWatcher()
    private var lastExternalApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    private var clipboardTimer: Timer?
    private var lastClipboardChange = NSPasteboard.general.changeCount

    init(
        persistence: PersistenceStore = .shared,
        pluginManager: PluginManager = PluginManager(),
        credentialStore: CredentialStore = CredentialStore()
    ) {
        self.persistence = persistence
        self.pluginManager = pluginManager
        self.credentialStore = credentialStore
        history = persistence.load([HistoryItem].self, from: "history.json", fallback: [])
        var loadedServices = persistence.load([TranslationServiceConfig].self, from: "services.json", fallback: TranslationServiceConfig.defaults)
        let migratableKinds: Set<ServiceKind> = [.appleLocal, .google, .microsoft, .baidu, .youdao, .caiyun, .niu, .qwen, .deepseek, .kimi, .glm]
        for defaultService in TranslationServiceConfig.defaults where migratableKinds.contains(defaultService.kind) {
            if !loadedServices.contains(where: { $0.kind == defaultService.kind }) {
                loadedServices.append(defaultService)
            }
        }
        services = loadedServices.map { service in
            var service = service
            if let secret = credentialStore.value(for: service.id.uuidString) {
                service.apiKey = secret
            } else if !service.apiKey.isEmpty {
                credentialStore.set(service.apiKey, for: service.id.uuidString)
            }
            if let secondary = credentialStore.value(for: service.id.uuidString + ".secret") {
                service.secretKey = secondary
            } else if let secondary = service.secretKey, !secondary.isEmpty {
                credentialStore.set(secondary, for: service.id.uuidString + ".secret")
            }
            if service.kind == .microsoft,
               service.endpoint == "https://api.cognitive.microsofttranslator.com/translate",
               service.apiKey.isEmpty {
                service.endpoint = "https://api-edge.cognitive.microsofttranslator.com/translate"
                service.enabled = true
            }
            if service.kind == .microsoft, service.region == nil, !service.model.isEmpty {
                service.region = service.model
                service.model = ""
            }
            return service
        }
        settings = persistence.load(AppSettings.self, from: "settings.json", fallback: AppSettings())
        let savedPlugins = persistence.load([InstalledPlugin].self, from: "plugins.json", fallback: [])
        plugins = pluginManager.discover(previous: savedPlugins)
        configureHotKeys()
        configureSelectionPopup()
        observeFrontmostApplication()
    }

    func translate(mode: String = "输入翻译") async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { show("请输入要翻译的内容"); return }
        let allEnabledServices = services.filter(\.enabled)
        let enabledServices = Array(allEnabledServices.prefix(10))
        let enabledPlugins = plugins.filter(\.enabled)
        guard !enabledServices.isEmpty || !enabledPlugins.isEmpty else { show(TransError.noEnabledService.localizedDescription); return }
        isTranslating = true
        outputs = []
        if allEnabledServices.count > 10 { show("文本翻译服务最多同时调用 10 个，本次使用前 10 个") }

        await withTaskGroup(of: TranslationOutput.self) { group in
            for service in enabledServices {
                group.addTask { [translationClient, sourceLanguage, targetLanguage] in
                    await translationClient.translate(text: text, source: sourceLanguage, target: targetLanguage, using: service)
                }
            }
            for await result in group { outputs.append(result) }
        }
        for plugin in enabledPlugins {
            outputs.append(pluginManager.translate(plugin: plugin, text: text, source: sourceLanguage, target: targetLanguage))
        }
        let configuredOrder = Dictionary(uniqueKeysWithValues: enabledServices.enumerated().map { ($0.element.id, $0.offset) })
        outputs.sort {
            (configuredOrder[$0.serviceID] ?? Int.max) < (configuredOrder[$1.serviceID] ?? Int.max)
        }
        isTranslating = false
        appendHistory(HistoryItem(
            sourceText: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            outputs: outputs,
            mode: mode
        ))
    }

    func translateSelection(silent: Bool = false) async {
        await restoreFocusToPreviousApp()
        do {
            sourceText = try await captureService.selectedText()
            if !silent { selectedSection = .translate; activate() }
            await translate(mode: silent ? "静默划词翻译" : "划词翻译")
            if silent, let text = outputs.first(where: { $0.error == nil })?.text { copy(text) }
        } catch { show(error.localizedDescription) }
    }

    /// Selection translation shown in the floating popup next to the cursor,
    /// without bringing the main window forward.
    func translateSelectionPopup() async {
        await restoreFocusToPreviousApp()
        do {
            let text = try await captureService.selectedText()
            await presentSelectionPopup(text: text, at: NSEvent.mouseLocation, force: true)
        } catch {
            selectionPopup.showMessage(error.localizedDescription, at: NSEvent.mouseLocation)
        }
    }

    func translateInputBox() async {
        await restoreFocusToPreviousApp()
        do {
            sourceText = try await captureService.selectedText()
            await translate(mode: "输入框翻译")
            guard let text = outputs.first(where: { $0.error == nil })?.text else {
                throw TransError.service("翻译服务没有返回可用结果")
            }
            try await captureService.replaceSelection(with: text)
        } catch { show(error.localizedDescription) }
    }

    func swapLanguages() {
        let wasAuto = sourceLanguage == .auto
        let swapped = LanguageSwapPolicy.swapped(source: sourceLanguage, target: targetLanguage)
        sourceLanguage = swapped.source
        targetLanguage = swapped.target
        guard !wasAuto else { return }
        if let best = outputs.first(where: { $0.error == nil })?.text {
            sourceText = best
            outputs = []
        }
    }

    func chooseAndRecognize() async {
        let images = captureService.chooseImages()
        guard !images.isEmpty else { return }
        ocrText = ""
        ocrBlocks = []
        qrCodes = []
        for (index, image) in images.enumerated() {
            await recognize(image: image, mode: "选图 OCR", shouldTranslate: false, append: index > 0)
        }
        if settings.autoTranslate, !ocrText.isEmpty {
            sourceText = ocrText
            selectedSection = .translate
            await translate(mode: "多图 OCR 翻译")
        }
    }

    func screenshotAndRecognize(silent: Bool = false) async {
        do {
            let image = try await captureService.interactiveScreenshot()
            await recognize(image: image, mode: silent ? "静默截图 OCR" : "截图 OCR")
            if !silent { selectedSection = .ocr; activate() }
        } catch { show(error.localizedDescription) }
    }

    func screenshotAndTranslate() async {
        do {
            let image = try await captureService.interactiveScreenshot()
            await recognize(image: image, mode: "截图翻译", shouldTranslate: true)
            selectedSection = .translate
            activate()
        } catch { show(error.localizedDescription) }
    }

    func recognizeClipboard() async {
        guard let image = captureService.imageFromPasteboard() else { show("剪贴板中没有图片"); return }
        await recognize(image: image, mode: "剪贴板 OCR")
    }

    func recognize(image: NSImage, mode: String, shouldTranslate: Bool? = nil, append: Bool = false) async {
        isRecognizing = true
        ocrImage = image
        do {
            let result = try await ocrService.recognize(
                image: image,
                languages: [sourceLanguage],
                smartParagraphs: settings.smartParagraphs
            )
            let shouldAppend = append || (continuousOCR && !ocrText.isEmpty)
            if shouldAppend {
                ocrBlocks.append(contentsOf: result.blocks)
                if !result.text.isEmpty { ocrText += (ocrText.isEmpty ? "" : "\n\n") + result.text }
                qrCodes.append(contentsOf: result.qrCodes.filter { !qrCodes.contains($0) })
            } else {
                ocrBlocks = result.blocks
                ocrText = result.text
                qrCodes = result.qrCodes
            }
            if settings.copyAfterOCR {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ocrText, forType: .string)
            }
            if (shouldTranslate ?? settings.autoTranslate), !result.text.isEmpty {
                sourceText = ocrText
                selectedSection = .translate
                await translate(mode: mode)
            }
        } catch { show(error.localizedDescription) }
        isRecognizing = false
    }

    func toggleContinuousOCR() {
        continuousOCR.toggle()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        guard continuousOCR else { return }
        lastClipboardChange = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      NSPasteboard.general.changeCount != self.lastClipboardChange,
                      let image = self.captureService.imageFromPasteboard() else { return }
                self.lastClipboardChange = NSPasteboard.general.changeCount
                await self.recognize(image: image, mode: "连续 OCR")
            }
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("已复制")
    }

    func speak(_ text: String, language: Language) { speechService.speak(text, language: language) }

    func restore(_ item: HistoryItem) {
        sourceText = item.sourceText
        sourceLanguage = item.sourceLanguage
        targetLanguage = item.targetLanguage
        outputs = item.outputs
        selectedSection = .translate
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].isFavorite.toggle()
        saveHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
    }

    func clearHistory() { history.removeAll(); saveHistory() }

    func saveServices() {
        for service in services {
            credentialStore.set(service.apiKey, for: service.id.uuidString)
            credentialStore.set(service.secretKey ?? "", for: service.id.uuidString + ".secret")
        }
        let sanitized = services.map { service in
            var service = service
            service.apiKey = ""
            service.secretKey = nil
            return service
        }
        persistence.save(sanitized, to: "services.json")
    }
    func saveSettings() { persistence.save(settings, to: "settings.json") }
    func savePlugins() { persistence.save(plugins, to: "plugins.json") }

    @discardableResult
    func addService(kind: ServiceKind = .openAI) -> UUID {
        let service = TranslationServiceConfig.preset(for: kind)
        services.append(service)
        saveServices()
        return service.id
    }

    func removeService(_ id: UUID) {
        credentialStore.remove(id.uuidString)
        credentialStore.remove(id.uuidString + ".secret")
        services.removeAll { $0.id == id }
        saveServices()
    }

    func moveService(_ id: UUID, offset: Int) {
        guard let source = services.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(source + offset, 0), services.count - 1)
        guard source != destination else { return }
        services.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        saveServices()
    }

    func validateService(_ id: UUID) async {
        guard let service = services.first(where: { $0.id == id }) else { return }
        serviceValidation[id] = "正在验证…"
        let output = await translationClient.translate(
            text: "Hello",
            source: .english,
            target: .zhHans,
            using: service
        )
        if let error = output.error {
            serviceValidation[id] = "验证失败：\(error)"
        } else {
            serviceValidation[id] = "验证成功：\(output.text)"
        }
    }

    func installPlugin() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择包含 manifest.json 和 main.js 的 Trans 插件目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try pluginManager.install(from: url, previous: plugins)
            plugins = pluginManager.discover(previous: plugins)
            savePlugins()
        } catch { show(error.localizedDescription) }
    }

    func uninstallPlugin(_ plugin: InstalledPlugin) {
        do { try pluginManager.uninstall(plugin); plugins.removeAll { $0.id == plugin.id }; savePlugins() }
        catch { show(error.localizedDescription) }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Trans-历史记录.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try persistence.exportHistory(history, to: url); show("历史记录已导出") }
        catch { show("导出失败：\(error.localizedDescription)") }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled
            saveSettings()
        } catch {
            settings.launchAtLogin = false
            show("登录启动设置失败：请先使用打包后的 Trans.app 运行（\(error.localizedDescription)）")
        }
    }

    func runPermissionSelfTest() async {
        permissionTestResult = "正在测试辅助功能权限和文本读取…"
        permissionTestResult = await captureService.runAccessibilitySelfTest()
    }

    func handle(url: URL) {
        guard url.scheme == "trans" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host {
        case "translate":
            if let text = components?.queryItems?.first(where: { $0.name == "text" })?.value {
                sourceText = text
                selectedSection = .translate
                activate()
                Task { await translate(mode: "URL Scheme") }
            }
        case "screenshot": Task { await screenshotAndTranslate() }
        case "ocr": Task { await screenshotAndRecognize() }
        case "selection": Task { await translateSelection() }
        default: break
        }
    }

    private func configureHotKeys() {
        hotKeys.handler = { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                switch action {
                case .selection: await self.translateSelectionPopup()
                case .screenshot: await self.screenshotAndRecognize(silent: false)
                case .input: self.selectedSection = .translate; self.activate()
                case .ocr: await self.screenshotAndRecognize(silent: true)
                case .inputBox: await self.translateInputBox()
                }
            }
        }
        hotKeys.start()
        hotKeyWarning = HotKeyRegistrationReport.warningMessage(failedShortcuts: hotKeys.failedShortcuts)
    }

    private func configureSelectionPopup() {
        selectionPopup.onOpenInMainWindow = { [weak self] in
            guard let self else { return }
            let text = selectionPopup.state.sourceText
            if !text.isEmpty { sourceText = text }
            if !selectionPopup.state.outputs.isEmpty { outputs = selectionPopup.state.outputs }
            selectedSection = .translate
            activate()
        }
        selectionWatcher.onSelection = { [weak self] text, location in
            guard let self else { return }
            Task { await self.presentSelectionPopup(text: text, at: location) }
        }
        if settings.selectionPopupEnabled { selectionWatcher.start() }
    }

    func setSelectionPopupEnabled(_ enabled: Bool) {
        settings.selectionPopupEnabled = enabled
        saveSettings()
        if enabled {
            selectionWatcher.start()
        } else {
            selectionWatcher.stop()
            selectionPopup.dismiss()
        }
    }

    private func presentSelectionPopup(text: String, at location: CGPoint, force: Bool = false) async {
        guard force || SelectionPresentationPolicy.shouldPresent(
            text: text,
            lastShownText: selectionPopup.lastShownText,
            isPopupVisible: selectionPopup.isVisible
        ) else { return }
        selectionPopup.show(text: text, source: sourceLanguage, target: targetLanguage, at: location)
        let results = await translateOutputs(for: text)
        // A newer selection may have replaced this popup while we were translating.
        guard selectionPopup.state.sourceText == text else { return }
        if results.isEmpty {
            selectionPopup.fail(message: TransError.noEnabledService.localizedDescription)
            return
        }
        selectionPopup.update(outputs: results)
        appendHistory(HistoryItem(
            sourceText: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            outputs: results,
            mode: "划词翻译"
        ))
    }

    private func translateOutputs(for text: String) async -> [TranslationOutput] {
        let enabledServices = Array(services.filter(\.enabled).prefix(10))
        let enabledPlugins = plugins.filter(\.enabled)
        guard !enabledServices.isEmpty || !enabledPlugins.isEmpty else { return [] }
        var results: [TranslationOutput] = []
        await withTaskGroup(of: TranslationOutput.self) { group in
            for service in enabledServices {
                group.addTask { [translationClient, sourceLanguage, targetLanguage] in
                    await translationClient.translate(text: text, source: sourceLanguage, target: targetLanguage, using: service)
                }
            }
            for await result in group { results.append(result) }
        }
        for plugin in enabledPlugins {
            results.append(pluginManager.translate(plugin: plugin, text: text, source: sourceLanguage, target: targetLanguage))
        }
        let order = Dictionary(uniqueKeysWithValues: enabledServices.enumerated().map { ($0.element.id, $0.offset) })
        results.sort { (order[$0.serviceID] ?? .max) < (order[$1.serviceID] ?? .max) }
        return results
    }

    private func observeFrontmostApplication() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
    }

    /// Menu-bar and in-app triggers make Trans the active app, which would point
    /// AX focus (and the simulated Cmd+C) at Trans itself. Hand focus back to
    /// the app that owns the selection before capturing.
    private func restoreFocusToPreviousApp() async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID,
              let target = lastExternalApp, !target.isTerminated else { return }
        target.activate()
        for _ in 0..<12 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func appendHistory(_ item: HistoryItem) {
        history.insert(item, at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
        saveHistory()
    }

    private func saveHistory() { persistence.save(history, to: "history.json") }
    private func activate() { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
    private func show(_ text: String) {
        statusMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if statusMessage == text { statusMessage = nil }
        }
    }
}
