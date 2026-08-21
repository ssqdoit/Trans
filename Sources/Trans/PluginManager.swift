import Foundation
import CryptoKit
import JavaScriptCore
import NaturalLanguage

final class PluginManager: @unchecked Sendable {
    private let root: URL
    private let executionQueue = DispatchQueue(label: "com.trans.plugins", qos: .userInitiated)
    private let builtInIdentifiers = Set(BuiltInPlugin.all.map(\.manifest.identifier))

    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let target = root ?? base.appendingPathComponent("Trans/Plugins", isDirectory: true)
        self.root = target
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        installBuiltIns()
    }

    func discover(previous: [InstalledPlugin] = []) -> [InstalledPlugin] {
        let oldPlugins = Dictionary(uniqueKeysWithValues: previous.map { ($0.identifier, $0) })
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { plugin(at: $0, previous: oldPlugins[$0.lastPathComponent]) }
            .sorted {
                if $0.source != $1.source { return $0.source == .builtIn }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// Imports a native Trans plugin directory or a `.zip` package.
    func install(from source: URL, previous: [InstalledPlugin]) throws -> InstalledPlugin {
        let prepared = try preparePluginFolder(from: source)
        defer { if prepared.cleanup { try? FileManager.default.removeItem(at: prepared.url) } }

        let folder = try locatePluginRoot(in: prepared.url)
        try validatePluginFolder(folder)
        guard let manifest = loadManifest(at: folder) else {
            throw TransError.plugin("插件缺少有效的 manifest.json")
        }
        try validate(manifest: manifest, in: folder)
        guard !builtInIdentifiers.contains(manifest.identifier) else {
            throw TransError.plugin("该标识符由 Trans 内置插件保留")
        }

        let destination = root.appendingPathComponent(manifest.identifier, isDirectory: true)
        let staging = root.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        let backup = root.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: folder, to: staging)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: destination, to: backup)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            if FileManager.default.fileExists(atPath: backup.path),
               !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            throw error
        }

        let old = previous.first { $0.identifier == manifest.identifier }
        return makeInstalledPlugin(manifest, folder: destination, previous: old)
    }

    func uninstall(_ plugin: InstalledPlugin) throws {
        guard plugin.source != .builtIn else { throw TransError.plugin("内置插件不能卸载") }
        let url = URL(fileURLWithPath: plugin.path).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(rootPath), url.deletingLastPathComponent() == root.standardizedFileURL else {
            throw TransError.plugin("拒绝删除插件目录之外的文件")
        }
        try FileManager.default.removeItem(at: url)
    }

    func translate(
        plugin: InstalledPlugin,
        text: String,
        source: Language,
        target: Language
    ) async -> TranslationOutput {
        await withCheckedContinuation { continuation in
            executionQueue.async { [self] in
                continuation.resume(returning: translateSynchronously(
                    plugin: plugin,
                    text: text,
                    source: source,
                    target: target
                ))
            }
        }
    }

    private func translateSynchronously(
        plugin: InstalledPlugin,
        text: String,
        source: Language,
        target: Language
    ) -> TranslationOutput {
        let started = Date()
        do {
            guard plugin.category == .translate else {
                throw TransError.plugin("Trans 当前仅支持运行文本翻译插件")
            }
            let folder = URL(fileURLWithPath: plugin.path)
            guard let manifest = loadManifest(at: folder) else { throw TransError.plugin("无法读取插件清单") }
            try validate(manifest: manifest, in: folder)
            let scriptURL = folder.appendingPathComponent(manifest.main ?? "main.js")
            let script = try String(contentsOf: scriptURL, encoding: .utf8)
            guard let context = JSContext() else { throw TransError.plugin("无法创建 JavaScript 环境") }

            var exception: String?
            context.exceptionHandler = { _, value in exception = value?.toString() }
            configure(context: context, plugin: plugin, manifest: manifest, folder: folder)
            context.evaluateScript(Self.moduleBootstrap, withSourceURL: scriptURL)
            context.evaluateScript(script, withSourceURL: scriptURL)
            if let exception { throw TransError.plugin(exception) }
            guard let function = context.objectForKeyedSubscript("translate"), !function.isUndefined else {
                throw TransError.plugin("插件未导出 translate 函数")
            }

            let from = Self.languageCode(source)
            let to = Self.languageCode(target)
            let detected = source == .auto
                ? (NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en")
                : from
            var completionValue: Any?
            var streamValue: Any?
            let completion: @convention(block) (JSValue) -> Void = { value in
                completionValue = value.toObject()
            }
            let stream: @convention(block) (JSValue) -> Void = { value in
                streamValue = value.toObject()
            }
            let query: NSMutableDictionary = [
                "text": text,
                "originalText": text,
                "from": from,
                "to": to,
                "detectFrom": detected,
                "detectTo": to,
                "onCompletion": completion,
                "onStream": stream
            ]
            let returned = function.call(withArguments: [query, completion])
            if let exception { throw TransError.plugin(exception) }
            var promiseError: String?
            if completionValue == nil,
               let returned,
               returned.hasProperty("then") {
                let resolved: @convention(block) (JSValue) -> Void = { value in
                    if !value.isUndefined { completionValue = value.toObject() }
                }
                let rejected: @convention(block) (JSValue) -> Void = { value in
                    promiseError = value.toString()
                }
                returned.invokeMethod("then", withArguments: [resolved, rejected])
                context.evaluateScript("void 0")
            }
            if let promiseError { throw TransError.plugin(promiseError) }

            let rawValue = completionValue ?? returned?.toObject() ?? streamValue
            let parsed = try Self.parseTranslationResult(rawValue)
            return TranslationOutput(
                serviceID: UUID(),
                serviceName: plugin.name,
                text: parsed.text,
                detectedLanguage: parsed.detectedLanguage,
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

    private func configure(
        context: JSContext,
        plugin: InstalledPlugin,
        manifest: PluginManifest,
        folder: URL
    ) {
        let values = Dictionary(uniqueKeysWithValues: manifest.options.map {
            ($0.identifier, plugin.optionValues[$0.identifier] ?? $0.defaultValue ?? "")
        })
        context.setObject([
            "identifier": manifest.identifier,
            "name": manifest.name,
            "version": manifest.version,
            "category": manifest.category.rawValue,
            "summary": manifest.summary ?? "",
            "author": manifest.author ?? ""
        ], forKeyedSubscript: "transInfo" as NSString)
        context.setObject(values, forKeyedSubscript: "transOptions" as NSString)
        context.setObject([
            "appVersion": "1.0.0",
            "platform": "macOS",
            "isTrans": true
        ], forKeyedSubscript: "transEnv" as NSString)

        let log: @convention(block) (JSValue) -> Void = { value in
            NSLog("[Trans Plugin: %@] %@", manifest.identifier, value.toString())
        }
        let logObject = JSValue(newObjectIn: context)
        ["debug", "info", "warning", "warn", "error"].forEach {
            logObject?.setObject(log, forKeyedSubscript: $0 as NSString)
        }
        context.setObject(logObject, forKeyedSubscript: "transLog" as NSString)

        let transform: @convention(block) (String, String) -> String = { text, mode in
            Self.transform(text, mode: mode)
        }
        let resolveModule: @convention(block) (String, String) -> NSDictionary? = { name, parent in
            Self.resolveModule(name: name, parent: parent, folder: folder)
        }
        let crypto: @convention(block) (String, String, String) -> NSDictionary = { operation, value, key in
            Self.crypto(operation: operation, value: value, key: key)
        }
        let transObject = JSValue(newObjectIn: context)
        transObject?.setObject(transform, forKeyedSubscript: "transform" as NSString)
        transObject?.setObject(resolveModule, forKeyedSubscript: "resolveModule" as NSString)
        transObject?.setObject(crypto, forKeyedSubscript: "crypto" as NSString)
        context.setObject(transObject, forKeyedSubscript: "$trans" as NSString)

        let request: @convention(block) (JSValue) -> NSDictionary = { options in
            Self.performHTTPRequest(options: options, forcedMethod: nil)
        }
        let get: @convention(block) (JSValue) -> NSDictionary = { options in
            Self.performHTTPRequest(options: options, forcedMethod: "GET")
        }
        let post: @convention(block) (JSValue) -> NSDictionary = { options in
            Self.performHTTPRequest(options: options, forcedMethod: "POST")
        }
        let streamRequest: @convention(block) (JSValue) -> NSDictionary = { options in
            Self.performHTTPRequest(options: options, forcedMethod: nil, stream: true)
        }
        let httpObject = JSValue(newObjectIn: context)
        httpObject?.setObject(request, forKeyedSubscript: "request" as NSString)
        httpObject?.setObject(get, forKeyedSubscript: "get" as NSString)
        httpObject?.setObject(post, forKeyedSubscript: "post" as NSString)
        httpObject?.setObject(streamRequest, forKeyedSubscript: "streamRequest" as NSString)
        context.setObject(httpObject, forKeyedSubscript: "transHTTP" as NSString)
    }

    private func plugin(at url: URL, previous: InstalledPlugin?) -> InstalledPlugin? {
        guard let manifest = loadManifest(at: url), (try? validate(manifest: manifest, in: url)) != nil else {
            return nil
        }
        return makeInstalledPlugin(manifest, folder: url, previous: previous)
    }

    private func makeInstalledPlugin(
        _ manifest: PluginManifest,
        folder: URL,
        previous: InstalledPlugin?
    ) -> InstalledPlugin {
        let defaults = Dictionary(uniqueKeysWithValues: manifest.options.map {
            ($0.identifier, $0.defaultValue ?? "")
        })
        let savedValues = previous?.optionValues ?? [:]
        return InstalledPlugin(
            identifier: manifest.identifier,
            name: manifest.name,
            version: manifest.version,
            path: folder.path,
            enabled: manifest.category.isSupported ? (previous?.enabled ?? defaultEnabled(for: manifest)) : false,
            author: manifest.author,
            summary: manifest.summary,
            category: manifest.category,
            source: builtInIdentifiers.contains(manifest.identifier) ? .builtIn : source(of: folder),
            homepage: manifest.homepage,
            options: manifest.options,
            optionValues: defaults.merging(savedValues) { _, saved in saved }
        )
    }

    private func defaultEnabled(for manifest: PluginManifest) -> Bool {
        !builtInIdentifiers.contains(manifest.identifier)
    }

    private func source(of folder: URL) -> PluginSource {
        .trans
    }

    private func loadManifest(at folder: URL) -> PluginManifest? {
        let url = folder.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: url),
           let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) {
            return manifest
        }
        return nil
    }

    private func validate(manifest: PluginManifest, in folder: URL) throws {
        let range = manifest.identifier.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        )
        guard range != nil, !manifest.identifier.contains("..") else {
            throw TransError.plugin("插件 identifier 不安全或格式无效")
        }
        let main = folder.appendingPathComponent(manifest.main ?? "main.js").standardizedFileURL
        let folderPath = folder.standardizedFileURL.path + "/"
        guard main.path.hasPrefix(folderPath), FileManager.default.fileExists(atPath: main.path) else {
            throw TransError.plugin("插件缺少有效的 main.js")
        }
    }

    private func preparePluginFolder(from source: URL) throws -> (url: URL, cleanup: Bool) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw TransError.plugin("找不到所选插件")
        }
        if isDirectory.boolValue { return (source, false) }
        guard source.pathExtension.lowercased() == "zip" else {
            throw TransError.plugin("请选择 .zip 或插件目录")
        }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransPlugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", source.path, temporary.path]
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw TransError.plugin("无法解压插件包\(detail.isEmpty ? "" : "：\(detail)")")
            }
            return (temporary, true)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func locatePluginRoot(in source: URL) throws -> URL {
        if loadManifest(at: source) != nil { return source }
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw TransError.plugin("无法读取插件包") }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - source.pathComponents.count
            if depth > 4 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "manifest.json",
               loadManifest(at: url.deletingLastPathComponent()) != nil {
                candidates.append(url.deletingLastPathComponent())
            }
        }
        let unique = Array(Set(candidates.map(\.standardizedFileURL)))
        guard unique.count == 1, let folder = unique.first else {
            throw TransError.plugin(unique.isEmpty ? "插件包中没有有效的 manifest.json" : "插件包中包含多个插件")
        }
        return folder
    }

    private func validatePluginFolder(_ folder: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw TransError.plugin("无法读取插件目录") }
        var count = 0
        var totalSize = 0
        for case let url as URL in enumerator {
            count += 1
            guard count <= 2_000 else { throw TransError.plugin("插件包含过多文件") }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw TransError.plugin("插件包不能包含符号链接") }
            if values.isRegularFile == true { totalSize += values.fileSize ?? 0 }
            guard totalSize <= 100 * 1_024 * 1_024 else { throw TransError.plugin("插件包超过 100 MB") }
        }
    }

    private func installBuiltIns() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for plugin in BuiltInPlugin.all {
            let folder = root.appendingPathComponent(plugin.manifest.identifier, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let info = try encoder.encode(plugin.manifest)
                try info.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
                try Data(plugin.script.utf8).write(to: folder.appendingPathComponent("main.js"), options: .atomic)
            } catch {
                NSLog("Unable to install built-in plugin %@: %@", plugin.manifest.identifier, error.localizedDescription)
            }
        }
    }
}

private extension PluginManager {
    static let moduleBootstrap = #"""
    var __transModules = {};
    function require(name) { return __transLoadModule(name, "main.js"); }
    function __transLoadModule(name, parent) {
        var resolved = $trans.resolveModule(name, parent);
        if (!resolved) throw new Error("Unsupported module: " + name);
        if (__transModules[resolved.path]) return __transModules[resolved.path].exports;
        var module = { exports: {} };
        __transModules[resolved.path] = module;
        var localRequire = function(child) { return __transLoadModule(child, resolved.path); };
        var wrapper = eval("(function(module, exports, require, __filename, __dirname) {\n" + resolved.source + "\n})");
        var slash = resolved.path.lastIndexOf("/");
        wrapper(module, module.exports, localRequire, resolved.path, slash < 0 ? "." : resolved.path.slice(0, slash));
        return module.exports;
    }
    """#

    static func resolveModule(name: String, parent: String, folder: URL) -> NSDictionary? {
        if name == "$util" { return ["path": "$util", "source": utilModule] }
        if name == "crypto-js" { return ["path": "crypto-js", "source": cryptoModule] }
        let parentFolder = URL(fileURLWithPath: parent).deletingLastPathComponent().path
        var relativeCandidates: [String] = []
        if name.hasPrefix(".") {
            relativeCandidates.append(URL(fileURLWithPath: parentFolder).appendingPathComponent(name).path)
        } else {
            relativeCandidates += [
                "node_modules/\(name)/index.js",
                "node_modules/\(name)/\(name).js",
                "\(name).js",
                "lib/\(name).js"
            ]
        }
        var candidates: [String] = []
        for candidate in relativeCandidates {
            candidates.append(candidate)
            if !candidate.hasSuffix(".js") { candidates += [candidate + ".js", candidate + "/index.js"] }
        }
        let rootPath = folder.standardizedFileURL.path + "/"
        for relative in candidates {
            let url = folder.appendingPathComponent(relative).standardizedFileURL
            guard url.path.hasPrefix(rootPath),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = String(url.path.dropFirst(rootPath.count))
            return ["path": path, "source": source]
        }
        return nil
    }

    static let utilModule = #"""
    function type(x) {
        if (x === null) return "null";
        if (Array.isArray(x)) return "array";
        return typeof x;
    }
    function isNil(x) { return x === undefined || x === null; }
    function get(obj, path, fallback) {
        var keys = Array.isArray(path) ? path : [path];
        var value = obj;
        for (var i = 0; i < keys.length; i++) {
            if (isNil(value) || typeof value !== "object") return fallback;
            value = value[keys[i]];
        }
        return isNil(value) ? fallback : value;
    }
    module.exports = { type: type, isNil: isNil, get: get };
    """#

    /// A compact compatibility layer for the CryptoJS calls most translation
    /// plugins use for signing requests. Plugins needing AES or custom word
    /// array manipulation should bundle their own crypto-js implementation.
    static let cryptoModule = #"""
    var enc = {
        Hex: { name: "hex" },
        Base64: { name: "base64" },
        Utf8: { name: "utf8" }
    };
    function value(input) {
        if (input && input.__text !== undefined) return input.__text;
        return String(input === undefined || input === null ? "" : input);
    }
    function word(result, text) {
        return {
            __result: result,
            __text: text,
            toString: function(encoder) {
                return encoder === enc.Base64 ? result.base64 : result.hex;
            }
        };
    }
    enc.Utf8.parse = function(input) {
        var text = value(input);
        return word($trans.crypto("raw", text, ""), text);
    };
    enc.Utf8.stringify = function(input) { return value(input); };
    enc.Base64.stringify = function(input) { return input.__result.base64; };
    enc.Hex.stringify = function(input) { return input.__result.hex; };
    function digest(operation, input, key) {
        var text = value(input);
        return word($trans.crypto(operation, text, value(key)), text);
    }
    module.exports = {
        enc: enc,
        MD5: function(input) { return digest("md5", input, ""); },
        SHA1: function(input) { return digest("sha1", input, ""); },
        SHA256: function(input) { return digest("sha256", input, ""); },
        HmacSHA1: function(input, key) { return digest("hmac-sha1", input, key); },
        HmacSHA256: function(input, key) { return digest("hmac-sha256", input, key); }
    };
    """#

    static func crypto(operation: String, value: String, key: String) -> NSDictionary {
        let data = Data(value.utf8)
        let digest: Data
        switch operation {
        case "md5": digest = Data(Insecure.MD5.hash(data: data))
        case "sha1": digest = Data(Insecure.SHA1.hash(data: data))
        case "sha256": digest = Data(SHA256.hash(data: data))
        case "hmac-sha1":
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(
                for: data,
                using: SymmetricKey(data: Data(key.utf8))
            ))
        case "hmac-sha256":
            digest = Data(HMAC<SHA256>.authenticationCode(
                for: data,
                using: SymmetricKey(data: Data(key.utf8))
            ))
        default: digest = data
        }
        return [
            "hex": digest.map { String(format: "%02x", $0) }.joined(),
            "base64": digest.base64EncodedString()
        ]
    }

    static func performHTTPRequest(
        options: JSValue,
        forcedMethod: String?,
        stream: Bool = false
    ) -> NSDictionary {
        let object = options.toDictionary() ?? [:]
        let handler = options.forProperty("handler")
        let streamHandler = options.forProperty("streamHandler")
        guard let urlString = object["url"] as? String, var components = URLComponents(string: urlString) else {
            let result: NSDictionary = ["error": ["message": "URL 无效"]]
            handler?.call(withArguments: [result])
            return result
        }
        let method = (forcedMethod ?? object["method"] as? String ?? "GET").uppercased()
        let headers = (object["header"] as? [String: Any]) ?? (object["headers"] as? [String: Any]) ?? [:]
        let body = object["body"]
        if ["GET", "HEAD", "DELETE"].contains(method), let parameters = body as? [String: Any] {
            var items = components.queryItems ?? []
            items += parameters.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
            components.queryItems = items
        }
        guard let url = components.url else {
            let result: NSDictionary = ["error": ["message": "URL 无效"]]
            handler?.call(withArguments: [result])
            return result
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.setValue(String(describing: $0.value), forHTTPHeaderField: $0.key) }
        request.timeoutInterval = min(max(object["timeout"] as? Double ?? 60, 1), 300)
        if !["GET", "HEAD", "DELETE"].contains(method), let body {
            let contentType = request.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("application/json"), JSONSerialization.isValidJSONObject(body) {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            } else if let parameters = body as? [String: Any] {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                var encoded = URLComponents()
                encoded.queryItems = parameters.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
                request.httpBody = encoded.percentEncodedQuery?.data(using: .utf8)
            } else if let string = body as? String {
                request.httpBody = Data(string.utf8)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var urlResponse: URLResponse?
        var requestError: Error?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            urlResponse = response
            requestError = error
            semaphore.signal()
        }
        task.resume()
        let wait = semaphore.wait(timeout: .now() + request.timeoutInterval + 1)
        if wait == .timedOut { task.cancel() }

        if let error = requestError {
            let result: NSDictionary = ["error": [
                "message": error.localizedDescription,
                "localizedDescription": error.localizedDescription
            ]]
            handler?.call(withArguments: [result])
            return result
        }
        guard wait == .success, let data = responseData else {
            let result: NSDictionary = ["error": ["message": "网络请求超时"]]
            handler?.call(withArguments: [result])
            return result
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        let parsed = (try? JSONSerialization.jsonObject(with: data)) ?? text
        let http = urlResponse as? HTTPURLResponse
        let response: [String: Any] = [
            "url": urlResponse?.url?.absoluteString ?? url.absoluteString,
            "MIMEType": urlResponse?.mimeType ?? "",
            "expectedContentLength": urlResponse?.expectedContentLength ?? data.count,
            "textEncodingName": urlResponse?.textEncodingName ?? "",
            "suggestedFilename": urlResponse?.suggestedFilename ?? "",
            "statusCode": http?.statusCode ?? 0,
            "headers": http?.allHeaderFields ?? [:]
        ]
        if stream, let streamHandler, !streamHandler.isUndefined {
            streamHandler.call(withArguments: [["text": text, "rawData": Array(data)]])
        }
        let result: NSDictionary = ["data": parsed, "rawData": Array(data), "response": response]
        handler?.call(withArguments: [result])
        return result
    }

    static func parseTranslationResult(_ raw: Any?) throws -> (text: String, detectedLanguage: String?) {
        guard let raw else { throw TransError.plugin("插件没有返回翻译结果") }
        if let text = raw as? String { return (text, nil) }
        guard var object = dictionary(raw) else { throw TransError.plugin("插件返回了无法识别的数据") }
        if let error = dictionary(object["error"]) {
            let message = error["message"] as? String
                ?? error["localizedDescription"] as? String
                ?? "插件执行失败"
            throw TransError.plugin(message)
        }
        if let result = dictionary(object["result"]) { object = result }
        if let text = object["text"] as? String {
            return (text, object["detectedLanguage"] as? String ?? object["from"] as? String)
        }

        var sections: [String] = []
        if let think = dictionary(object["thinkInfo"])?["content"] as? String, !think.isEmpty {
            sections.append("思考过程\n\(think)")
        }
        if let paragraphs = object["toParagraphs"] as? [String] {
            sections.append(paragraphs.joined(separator: "\n\n"))
        } else if let paragraphs = object["toParagraphs"] as? [Any] {
            sections.append(paragraphs.compactMap { $0 as? String }.joined(separator: "\n\n"))
        }
        if let dictionary = dictionary(object["toDict"]) { sections.append(formatDictionary(dictionary)) }
        let text = sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { throw TransError.plugin("插件结果中缺少 text、toParagraphs 或 toDict") }
        return (text, object["from"] as? String)
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let dictionary = value as? NSDictionary {
            return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
                guard let key = key as? String else { return nil }
                return (key, value)
            })
        }
        return nil
    }

    static func formatDictionary(_ dictionary: [String: Any]) -> String {
        var lines: [String] = []
        if let word = dictionary["word"] as? String { lines.append(word) }
        if let phonetics = dictionary["phonetics"] as? [Any] {
            let values = phonetics.compactMap { item -> String? in
                guard let value = self.dictionary(item), let phonetic = value["value"] as? String else { return nil }
                let type = (value["type"] as? String)?.uppercased() ?? ""
                return type.isEmpty ? phonetic : "\(type) /\(phonetic)/"
            }
            if !values.isEmpty { lines.append(values.joined(separator: " · ")) }
        }
        if let parts = dictionary["parts"] as? [Any] {
            for item in parts {
                guard let part = self.dictionary(item) else { continue }
                let name = part["part"] as? String ?? ""
                let means = (part["means"] as? [Any])?.compactMap { $0 as? String }.joined(separator: "；") ?? ""
                if !means.isEmpty { lines.append(name.isEmpty ? means : "\(name) \(means)") }
            }
        }
        if let additions = dictionary["additions"] as? [Any] {
            for item in additions {
                guard let addition = self.dictionary(item), let value = addition["value"] as? String else { continue }
                let name = addition["name"] as? String ?? ""
                lines.append(name.isEmpty ? value : "\(name)\n\(value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func languageCode(_ language: Language) -> String {
        switch language {
        case .zhHans: "zh-Hans"
        case .zhHant: "zh-Hant"
        default: language.code
        }
    }

    static func transform(_ text: String, mode: String) -> String {
        switch mode {
        case "simplified":
            return text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        case "traditional":
            return text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
        case "pinyin-tone": return text.applyingTransform(.mandarinToLatin, reverse: false) ?? text
        case "pinyin":
            return text.applyingTransform(.mandarinToLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false) ?? text
        case "upper": return text.uppercased()
        case "lower": return text.lowercased()
        case "url-decode": return text.removingPercentEncoding ?? text
        case "url-encode": return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case "json":
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let output = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            else { return text }
            return String(data: output, encoding: .utf8) ?? text
        case "clean":
            return text
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case "camel": return convertCase(text, separator: "", capitalizeFirst: false)
        case "pascal": return convertCase(text, separator: "", capitalizeFirst: true)
        case "snake": return convertCase(text, separator: "_", capitalizeFirst: false)
        case "kebab": return convertCase(text, separator: "-", capitalizeFirst: false)
        default: return text
        }
    }

    static func convertCase(_ text: String, separator: String, capitalizeFirst: Bool) -> String {
        let expanded = text.replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        let words = expanded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        guard separator.isEmpty else { return words.joined(separator: separator) }
        return words.enumerated().map { index, word in
            (index > 0 || capitalizeFirst) ? word.prefix(1).uppercased() + word.dropFirst() : word
        }.joined()
    }
}

private struct BuiltInPlugin {
    var manifest: PluginManifest
    var script: String

    static let all: [BuiltInPlugin] = [
        .init(
            manifest: .init(
                identifier: "com.trans.builtin.chinese-tools",
                name: "简繁与拼音",
                version: "1.0.0",
                author: "Trans",
                summary: "简繁转换，并可将汉字转换为带声调或无声调拼音",
                category: .translate,
                options: [.init(
                    identifier: "mode",
                    type: "menu",
                    title: "处理方式",
                    defaultValue: "traditional",
                    menuValues: [
                        .init(title: "简体转繁体", value: "traditional"),
                        .init(title: "繁体转简体", value: "simplified"),
                        .init(title: "带声调拼音", value: "pinyin-tone"),
                        .init(title: "无声调拼音", value: "pinyin")
                    ]
                )]
            ),
            script: #"""
            function supportLanguages() { return ["auto", "zh-Hans", "zh-Hant"]; }
            function translate(query, completion) {
                completion({ text: $trans.transform(query.text, transOptions.mode || "traditional"), detectedLanguage: query.detectFrom });
            }
            """#
        ),
        .init(
            manifest: .init(
                identifier: "com.trans.builtin.text-tools",
                name: "文本格式工具",
                version: "1.0.0",
                author: "Trans",
                summary: "清理文本、格式化 JSON、URL 编解码和代码命名转换",
                category: .translate,
                options: [.init(
                    identifier: "mode",
                    type: "menu",
                    title: "处理方式",
                    defaultValue: "clean",
                    menuValues: [
                        .init(title: "清理空白", value: "clean"),
                        .init(title: "格式化 JSON", value: "json"),
                        .init(title: "URL 解码", value: "url-decode"),
                        .init(title: "URL 编码", value: "url-encode"),
                        .init(title: "camelCase", value: "camel"),
                        .init(title: "PascalCase", value: "pascal"),
                        .init(title: "snake_case", value: "snake"),
                        .init(title: "kebab-case", value: "kebab"),
                        .init(title: "大写", value: "upper"),
                        .init(title: "小写", value: "lower")
                    ]
                )]
            ),
            script: #"""
            function supportLanguages() { return ["auto", "zh-Hans", "zh-Hant", "en"]; }
            function translate(query, completion) {
                completion({ text: $trans.transform(query.originalText || query.text, transOptions.mode || "clean") });
            }
            """#
        ),
        .init(
            manifest: .init(
                identifier: "com.trans.builtin.ai-writer",
                name: "AI 写作助手",
                version: "1.0.0",
                author: "Trans",
                summary: "使用 OpenAI 兼容接口执行翻译、润色、纠错、解释或自定义指令",
                category: .translate,
                options: [
                    .init(identifier: "endpoint", type: "text", title: "接口地址", defaultValue: "https://api.openai.com/v1/chat/completions", textConfig: .init(type: "visible", placeholderText: "OpenAI 兼容的 Chat Completions 地址")),
                    .init(identifier: "apiKey", type: "text", title: "API Key", textConfig: .init(type: "secure", placeholderText: "密钥保存在 macOS 钥匙串")),
                    .init(identifier: "model", type: "text", title: "模型", defaultValue: "gpt-4.1-mini", textConfig: .init(type: "visible", placeholderText: "模型名称")),
                    .init(identifier: "task", type: "menu", title: "任务", defaultValue: "translate", menuValues: [
                        .init(title: "高质量翻译", value: "translate"),
                        .init(title: "润色", value: "polish"),
                        .init(title: "语法纠错", value: "correct"),
                        .init(title: "解释", value: "explain"),
                        .init(title: "自定义指令", value: "custom")
                    ]),
                    .init(identifier: "customPrompt", type: "text", title: "自定义指令", defaultValue: "", textConfig: .init(type: "visible", height: 64, placeholderText: "仅在任务选择自定义指令时使用"))
                ]
            ),
            script: #"""
            function supportLanguages() { return ["auto", "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "pt", "ru", "it", "ar", "th", "vi"]; }
            function translate(query, completion) {
                var prompts = {
                    translate: "Translate the text faithfully and naturally from " + query.detectFrom + " to " + query.detectTo + ". Return only the translation.",
                    polish: "Polish the following text while preserving its meaning. Return only the polished text.",
                    correct: "Correct grammar, spelling and punctuation. Return only the corrected text.",
                    explain: "Explain the following text clearly in " + query.detectTo + ".",
                    custom: transOptions.customPrompt || "Process the following text."
                };
                if (!transOptions.endpoint || !transOptions.model) {
                    completion({ error: { message: "请先配置接口地址和模型" } }); return;
                }
                transHTTP.request({
                    method: "POST", url: transOptions.endpoint, timeout: 90,
                    header: { "Content-Type": "application/json", "Authorization": "Bearer " + (transOptions.apiKey || "") },
                    body: { model: transOptions.model, messages: [
                        { role: "system", content: prompts[transOptions.task || "translate"] },
                        { role: "user", content: query.originalText || query.text }
                    ] },
                    handler: function(resp) {
                        if (resp.error) { completion({ error: { message: resp.error.message || "网络请求失败" } }); return; }
                        var value = resp.data && resp.data.choices && resp.data.choices[0] && resp.data.choices[0].message && resp.data.choices[0].message.content;
                        if (!value) { completion({ error: { message: "AI 服务返回了无法识别的数据" } }); return; }
                        completion({ result: { toParagraphs: [value], from: query.detectFrom, to: query.detectTo } });
                    }
                });
            }
            """#
        )
    ]
}
