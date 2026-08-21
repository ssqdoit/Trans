import XCTest
@testable import Trans

final class PluginManagerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var pluginRoot: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransPluginTests-\(UUID().uuidString)", isDirectory: true)
        pluginRoot = temporaryDirectory.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDiscoversUsefulBuiltInPluginsWithIndependentEnabledStates() throws {
        let manager = PluginManager(root: pluginRoot)
        var plugins = manager.discover()

        XCTAssertEqual(plugins.filter { $0.source == .builtIn }.count, 3)
        XCTAssertEqual(plugins.first { $0.identifier == "com.trans.builtin.chinese-tools" }?.enabled, false)
        XCTAssertEqual(plugins.first { $0.identifier == "com.trans.builtin.text-tools" }?.enabled, false)
        XCTAssertEqual(plugins.first { $0.identifier == "com.trans.builtin.ai-writer" }?.enabled, false)

        let index = try XCTUnwrap(plugins.firstIndex { $0.identifier == "com.trans.builtin.text-tools" })
        plugins[index].enabled = true
        let rediscovered = manager.discover(previous: plugins)
        XCTAssertEqual(rediscovered.first { $0.identifier == "com.trans.builtin.text-tools" }?.enabled, true)
    }

    func testRunsBuiltInChineseConversion() async throws {
        let manager = PluginManager(root: pluginRoot)
        guard var plugin = manager.discover().first(where: {
            $0.identifier == "com.trans.builtin.chinese-tools"
        }) else { return XCTFail("缺少内置简繁插件") }
        plugin.optionValues["mode"] = "simplified"

        let output = await manager.translate(
            plugin: plugin,
            text: "繁體中文",
            source: .zhHant,
            target: .zhHans
        )

        XCTAssertNil(output.error)
        XCTAssertEqual(output.text, "繁体中文")
    }

    func testBuiltInPluginCannotBeUninstalled() throws {
        let manager = PluginManager(root: pluginRoot)
        let plugin = try XCTUnwrap(manager.discover().first { $0.source == .builtIn })

        XCTAssertThrowsError(try manager.uninstall(plugin))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plugin.path))
    }

    func testImportsAndRunsTransCallbackPluginWithOptions() async throws {
        let source = try makeTransPlugin(
            identifier: "com.example.trans.callback",
            infoExtras: #", "options": [{"identifier":"prefix","type":"text","title":"前缀","defaultValue":"默认：","textConfig":{"type":"visible"}}]"#,
            script: #"""
            function supportLanguages() { return ["auto", "en", "zh-Hans"]; }
            function translate(query, completion) {
                completion({ text: (transOptions.prefix || "") + query.text, detectedLanguage: query.detectFrom });
            }
            """#
        )
        let manager = PluginManager(root: pluginRoot)
        var plugin = try manager.install(from: source, previous: [])

        XCTAssertEqual(plugin.source, .trans)
        XCTAssertEqual(plugin.category, .translate)
        XCTAssertEqual(plugin.optionValues["prefix"], "默认：")
        plugin.optionValues["prefix"] = "Trans："

        let output = await manager.translate(
            plugin: plugin,
            text: "hello",
            source: .english,
            target: .zhHans
        )
        XCTAssertNil(output.error)
        XCTAssertEqual(output.text, "Trans：hello")
        XCTAssertEqual(output.detectedLanguage, "en")
    }

    func testImportsTransPluginArchive() throws {
        let source = try makeTransPlugin(
            identifier: "com.example.trans.archive",
            script: "function translate(query, completion) { completion({result:{toParagraphs:[query.text]}}); }"
        )
        let archive = temporaryDirectory.appendingPathComponent("Archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", source.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let manager = PluginManager(root: pluginRoot)
        let plugin = try manager.install(from: archive, previous: [])

        XCTAssertEqual(plugin.identifier, "com.example.trans.archive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plugin.path + "/main.js"))
    }

    func testRunsAsyncTransPluginAndBuiltInCryptoModule() async throws {
        let source = try makeTransPlugin(
            identifier: "com.example.trans.async",
            script: #"""
            async function translate(query) {
                var CryptoJS = require("crypto-js");
                return { result: { toParagraphs: [CryptoJS.MD5(query.text).toString()] } };
            }
            """#
        )
        let manager = PluginManager(root: pluginRoot)
        let plugin = try manager.install(from: source, previous: [])

        let output = await manager.translate(
            plugin: plugin,
            text: "hello",
            source: .english,
            target: .zhHans
        )

        XCTAssertNil(output.error)
        XCTAssertEqual(output.text, "5d41402abc4b2a76b9719d911017c592")
    }

    func testUnsupportedTransCategoryImportsDisabled() throws {
        let source = try makeTransPlugin(
            identifier: "com.example.trans.ocr",
            category: "ocr",
            script: "function ocr(query, completion) { completion({result:{texts:[]}}); }",
            mainName: "main.js"
        )
        // Validation requires a main.js, while category support is decided separately.
        let manager = PluginManager(root: pluginRoot)
        let plugin = try manager.install(from: source, previous: [])

        XCTAssertEqual(plugin.category, .ocr)
        XCTAssertFalse(plugin.enabled)
    }

    func testRejectsUnsafePluginIdentifier() throws {
        let source = try makeTransPlugin(
            identifier: "../escape",
            script: "function translate(query) { return query.text; }"
        )
        let manager = PluginManager(root: pluginRoot)

        XCTAssertThrowsError(try manager.install(from: source, previous: []))
    }

    private func makeTransPlugin(
        identifier: String,
        category: String = "translate",
        infoExtras: String = "",
        script: String,
        mainName: String = "main.js"
    ) throws -> URL {
        let folder = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"identifier":"\#(identifier)","version":"1.0.0","category":"\#(category)","name":"测试 Trans 插件","summary":"回归测试"\#(infoExtras)}"#
        try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        try Data(script.utf8).write(to: folder.appendingPathComponent(mainName))
        return folder
    }
}
