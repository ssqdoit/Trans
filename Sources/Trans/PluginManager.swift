import Foundation
import JavaScriptCore

final class PluginManager {
    private let root: URL

    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let target = root ?? base.appendingPathComponent("Trans/Plugins", isDirectory: true)
        let legacy = base.appendingPathComponent("Trans/Plugins", isDirectory: true)
        if root == nil,
           !FileManager.default.fileExists(atPath: target.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: legacy, to: target)
        }
        self.root = target
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func discover(previous: [InstalledPlugin] = []) -> [InstalledPlugin] {
        let oldStates = Dictionary(uniqueKeysWithValues: previous.map { ($0.identifier, $0.enabled) })
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { plugin(at: $0, enabled: oldStates) }.sorted { $0.name < $1.name }
    }

    func install(from source: URL, previous: [InstalledPlugin]) throws -> InstalledPlugin {
        guard let manifest = loadManifest(at: source) else { throw TransError.plugin("插件缺少有效的 manifest.json") }
        let destination = root.appendingPathComponent(manifest.identifier, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return InstalledPlugin(
            identifier: manifest.identifier,
            name: manifest.name,
            version: manifest.version,
            path: destination.path,
            enabled: true,
            author: manifest.author,
            summary: manifest.description
        )
    }

    func uninstall(_ plugin: InstalledPlugin) throws {
        let url = URL(fileURLWithPath: plugin.path)
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            throw TransError.plugin("拒绝删除插件目录之外的文件")
        }
        try FileManager.default.removeItem(at: url)
    }

    func translate(
        plugin: InstalledPlugin,
        text: String,
        source: Language,
        target: Language
    ) -> TranslationOutput {
        let started = Date()
        do {
            let folder = URL(fileURLWithPath: plugin.path)
            guard let manifest = loadManifest(at: folder) else { throw TransError.plugin("无法读取插件清单") }
            let scriptURL = folder.appendingPathComponent(manifest.main ?? "main.js")
            let script = try String(contentsOf: scriptURL, encoding: .utf8)
            guard let context = JSContext() else { throw TransError.plugin("无法创建 JavaScript 环境") }
            var exception: String?
            context.exceptionHandler = { _, value in exception = value?.toString() }
            context.setObject([
                "identifier": manifest.identifier,
                "name": manifest.name,
                "version": manifest.version
            ], forKeyedSubscript: "transInfo" as NSString)
            context.evaluateScript(script, withSourceURL: scriptURL)
            if let exception { throw TransError.plugin(exception) }
            guard let function = context.objectForKeyedSubscript("translate"), !function.isUndefined else {
                throw TransError.plugin("插件未导出 translate(request) 函数")
            }
            let request: [String: Any] = [
                "text": text,
                "from": source.code,
                "to": target.code
            ]
            let result = function.call(withArguments: [request])
            if let exception { throw TransError.plugin(exception) }
            let value = result?.toObject()
            let output: String
            let detected: String?
            if let text = value as? String {
                output = text
                detected = nil
            } else if let object = value as? [String: Any], let text = object["text"] as? String {
                output = text
                detected = object["detectedLanguage"] as? String
            } else {
                throw TransError.plugin("translate 返回值应为字符串或包含 text 的对象")
            }
            return TranslationOutput(
                serviceID: UUID(),
                serviceName: plugin.name,
                text: output,
                detectedLanguage: detected,
                duration: Date().timeIntervalSince(started)
            )
        } catch {
            return TranslationOutput(
                serviceID: UUID(),
                serviceName: plugin.name,
                text: "",
                duration: Date().timeIntervalSince(started),
                error: error.localizedDescription
            )
        }
    }

    private func plugin(at url: URL, enabled states: [String: Bool]) -> InstalledPlugin? {
        guard let manifest = loadManifest(at: url) else { return nil }
        return InstalledPlugin(
            identifier: manifest.identifier,
            name: manifest.name,
            version: manifest.version,
            path: url.path,
            enabled: states[manifest.identifier] ?? true,
            author: manifest.author,
            summary: manifest.description
        )
    }

    private func loadManifest(at folder: URL) -> PluginManifest? {
        let candidates = ["manifest.json", "manifest.json"]
        for name in candidates {
            let url = folder.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) {
                return manifest
            }
        }
        return nil
    }
}
