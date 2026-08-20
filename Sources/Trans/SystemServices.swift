import AppKit
import ApplicationServices
import AVFoundation
import Carbon

enum SelectionCapturePolicy {
    static func accepts(preflightTrusted: Bool, pasteboardChanged: Bool, text: String?) -> Bool {
        // TCC can report a stale preflight value after permission changes or app re-signing.
        // A successful copy is the authoritative capability check.
        pasteboardChanged && !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

enum ScreenshotSelectionPolicy {
    static func shouldWaitForModifierRelease(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option)
    }
}

@MainActor
final class CaptureService {
    func chooseImages() -> [NSImage] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic, .webP]
        panel.allowsMultipleSelection = true
        panel.message = "选择一张或多张需要识别的图片"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(NSImage.init(contentsOf:))
    }

    func imageFromPasteboard() -> NSImage? {
        NSImage(pasteboard: .general)
    }

    func interactiveScreenshot() async throws -> NSImage {
        while ScreenshotSelectionPolicy.shouldWaitForModifierRelease(NSEvent.modifierFlags) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trans-capture-\(UUID().uuidString).png")
        let path = url.path
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let image = NSImage(contentsOfFile: path) else {
                        throw TransError.imageUnavailable
                    }
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: image)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func selectedText() async throws -> String {
        let trusted = AXIsProcessTrusted()
        if let text = accessibilitySelectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        let before = pasteboard.changeCount

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        var text: String?
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 40_000_000)
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                break
            }
        }
        guard SelectionCapturePolicy.accepts(
            preflightTrusted: trusted,
            pasteboardChanged: pasteboard.changeCount != before,
            text: text
        ), let text else {
            if !trusted {
                _ = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary)
                throw TransError.permission(
                    "Trans 尚未获得当前版本的辅助功能权限。请在系统设置中移除旧的 Trans 条目，重新添加 \(Bundle.main.bundleURL.path)，然后完全退出并重开应用。"
                )
            }
            throw TransError.permission("辅助功能权限已生效，但没有复制到文本。请确认已在前台应用中选中文字，且该应用允许复制。")
        }
        if let old {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
        return text
    }

    func runAccessibilitySelfTest() async -> String {
        let marker = "Trans permission self-test \(UUID().uuidString)"
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 130),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Trans 辅助功能自测"
        panel.level = .floating
        let textView = NSTextView(frame: NSRect(x: 16, y: 16, width: 388, height: 76))
        textView.string = marker
        textView.isEditable = true
        panel.contentView?.addSubview(textView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: (marker as NSString).length))
        try? await Task.sleep(nanoseconds: 250_000_000)
        defer { panel.orderOut(nil); panel.close() }
        do {
            let captured = try await selectedText()
            if captured == marker {
                return "自测通过：辅助功能权限和选中文本读取均正常"
            }
            return "自测失败：读取到了其他文本（AX 权限：\(AXIsProcessTrusted() ? "已授权" : "未授权")）"
        } catch {
            return "自测失败：\(error.localizedDescription)（AX 权限：\(AXIsProcessTrusted() ? "已授权" : "未授权")，应用：\(Bundle.main.bundleURL.path)）"
        }
    }

    private func accessibilitySelectedText() -> String? {
        AXSelectionReader.selectedText()
    }

    func replaceSelection(with text: String) async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try await Task.sleep(nanoseconds: 80_000_000)
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    var isSpeaking: Bool { synthesizer.isSpeaking }
    func speak(_ text: String, language: Language) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate); return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language == .auto ? "en-US" : language.code)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}

@MainActor
final class HotKeyService {
    enum Action { case selection, screenshot, input, ocr, inputBox }
    private let signature: OSType = 0x54524E53 // TRNS
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    var handler: ((Action) -> Void)?
    private(set) var failedShortcuts: [String] = []

    func start() {
        stop()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The dispatcher target keeps hot keys firing while the app is in the
        // background; the application target is known to drop them there.
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.perform(id: hotKeyID.id) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        let bindings: [(UInt32, Int, String)] = [
            (UInt32(kVK_ANSI_S), 1, "⌥S"),
            (UInt32(kVK_ANSI_D), 2, "⌥D"),
            (UInt32(kVK_ANSI_A), 3, "⌥A"),
            (UInt32(kVK_ANSI_F), 4, "⌥F"),
            (UInt32(kVK_ANSI_T), 5, "⌥T")
        ]
        for (keyCode, id, label) in bindings {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
            if RegisterEventHotKey(
                keyCode,
                UInt32(optionKey),
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            ) == noErr {
                hotKeyRefs.append(ref)
            } else {
                failedShortcuts.append(label)
            }
        }
    }

    func stop() {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        hotKeyRefs.removeAll()
        failedShortcuts.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func perform(id: UInt32) {
        switch id {
        case 1: handler?(.selection)
        case 2: handler?(.screenshot)
        case 3: handler?(.input)
        case 4: handler?(.ocr)
        case 5: handler?(.inputBox)
        default: break
        }
    }

    deinit {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
