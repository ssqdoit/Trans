import AppKit
import SwiftUI

@MainActor
final class SelectionPopupState: ObservableObject {
    @Published var title = "划词翻译"
    @Published var sourceText = ""
    @Published var outputs: [TranslationOutput] = []
    @Published var isTranslating = false
    @Published var message: String?
    @Published var sourceLanguage: Language = .auto
    @Published var targetLanguage: Language = .zhHans
}

/// Borderless panel that can take key status for in-popup interaction without
/// activating Trans (.nonactivatingPanel keeps the source app frontmost).
private final class SelectionPopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SelectionPopupController {
    static let panelWidth: CGFloat = 380
    static let editDebounceNanoseconds: UInt64 = 800_000_000
    let state = SelectionPopupState()
    var onOpenInMainWindow: (() -> Void)?
    var onRetranslate: ((String) -> Void)?
    var onLanguagesChanged: ((Language, Language) -> Void)?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SelectionPopupView>?
    private var dismissMonitors: [Any] = []
    private var editDebounceTask: Task<Void, Never>?
    private var lastMouse = CGPoint.zero
    private(set) var lastShownText: String?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(text: String, title: String = "划词翻译", source: Language, target: Language, at mouse: CGPoint) {
        editDebounceTask?.cancel()
        state.title = title
        state.sourceText = text
        state.sourceLanguage = source
        state.targetLanguage = target
        state.outputs = []
        state.message = nil
        state.isTranslating = true
        lastShownText = text
        lastMouse = mouse
        presentAfterLayout()
    }

    func showMessage(_ message: String, title: String = "划词翻译", at mouse: CGPoint) {
        editDebounceTask?.cancel()
        state.title = title
        state.sourceText = ""
        state.outputs = []
        state.isTranslating = false
        state.message = message
        lastShownText = nil
        lastMouse = mouse
        presentAfterLayout()
    }

    /// Marks a retranslation in flight (edit or language change) without
    /// resetting the shown text or reopening the panel at a new location.
    func beginTranslating() {
        state.message = nil
        state.isTranslating = true
        if isVisible { presentAfterLayout() }
    }

    func update(outputs: [TranslationOutput]) {
        state.outputs = outputs
        state.isTranslating = false
        if isVisible { presentAfterLayout() }
    }

    func fail(message: String) {
        state.message = message
        state.isTranslating = false
        if isVisible { presentAfterLayout() }
    }

    func dismiss() {
        editDebounceTask?.cancel()
        removeDismissMonitors()
        panel?.orderOut(nil)
    }

    // MARK: - Editing / language plumbing (called from SelectionPopupView)

    fileprivate func sourceTextEdited() {
        let text = state.sourceText
        // show() assigns sourceText programmatically after setting
        // lastShownText, so only genuine user edits pass this guard.
        guard text != lastShownText else { return }
        lastShownText = text
        editDebounceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.outputs = []
            state.message = nil
            state.isTranslating = false
            return
        }
        editDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.editDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.onRetranslate?(self.state.sourceText)
        }
    }

    fileprivate func languagesEdited() {
        onLanguagesChanged?(state.sourceLanguage, state.targetLanguage)
    }

    fileprivate func swapLanguages() {
        let swapped = LanguageSwapPolicy.swapped(source: state.sourceLanguage, target: state.targetLanguage)
        state.sourceLanguage = swapped.source
        state.targetLanguage = swapped.target
        // The two Picker onChange handlers notify onLanguagesChanged with the
        // final pair; AppModel dedupes the repeated callback.
    }

    private func presentAfterLayout() {
        let panel = ensurePanel()
        // SwiftUI applies published changes on the next runloop pass; measure after that.
        DispatchQueue.main.async { [self] in
            guard let hostingView else { return }
            hostingView.layoutSubtreeIfNeeded()
            var size = hostingView.fittingSize
            size.width = Self.panelWidth
            size.height = min(max(size.height, 64), 460)
            let screen = Self.screenFrame(containing: lastMouse)
            let origin = PopupPlacement.origin(mouse: lastMouse, panelSize: size, screen: screen)
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
            if !panel.isVisible { panel.orderFrontRegardless() }
            installDismissMonitors()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: SelectionPopupView(
            state: state,
            onCopy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onOpenMain: { [weak self] in
                self?.onOpenInMainWindow?()
                self?.dismiss()
            },
            onClose: { [weak self] in self?.dismiss() },
            onEdit: { [weak self] in self?.sourceTextEdited() },
            onLanguageChange: { [weak self] in self?.languagesEdited() },
            onSwap: { [weak self] in self?.swapLanguages() }
        ))
        let panel = SelectionPopupPanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.panelWidth, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting
        self.panel = panel
        hostingView = hosting
        return panel
    }

    private func installDismissMonitors() {
        guard dismissMonitors.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
        )
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self else { return event }
                let inPopup = event.window is SelectionPopupPanel
                if event.type == .keyDown {
                    guard event.keyCode == 53, inPopup else { return event } // Esc
                    Task { @MainActor in self.dismiss() }
                    return nil
                }
                if !inPopup { Task { @MainActor in self.dismiss() } }
                return event
            }
        )
        dismissMonitors = [global, local].compactMap { $0 }
    }

    private func removeDismissMonitors() {
        for monitor in dismissMonitors { NSEvent.removeMonitor(monitor) }
        dismissMonitors.removeAll()
    }

    private static func screenFrame(containing point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
    }

    deinit {
        for monitor in dismissMonitors { NSEvent.removeMonitor(monitor) }
    }
}

struct SelectionPopupView: View {
    @ObservedObject var state: SelectionPopupState
    var onCopy: (String) -> Void
    var onOpenMain: () -> Void
    var onClose: () -> Void
    var onEdit: () -> Void
    var onLanguageChange: () -> Void
    var onSwap: () -> Void

    private var results: [TranslationOutput] {
        let succeeded = state.outputs.filter { $0.error == nil && !$0.text.isEmpty }
        return succeeded.isEmpty ? Array(state.outputs.prefix(1)) : succeeded
    }

    // showMessage() clears sourceText and sets message: a standalone notice
    // with no translation session, so the editor and language bar hide. An
    // in-session failure (fail()) keeps sourceText, so they stay editable.
    private var hasSession: Bool {
        state.message == nil || !state.sourceText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if hasSession {
                sourceEditor
                languageBar
            }
            Divider()
            content
        }
        .padding(12)
        .frame(width: SelectionPopupController.panelWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(state.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Button(action: onOpenMain) { Image(systemName: "macwindow") }
                .buttonStyle(.borderless).help("在主窗口中打开")
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("关闭")
        }
    }

    /// Editable source text, auto-sizing from 1 to ~4 lines: the hidden Text
    /// drives the height, the TextEditor scrolls beyond it.
    private var sourceEditor: some View {
        ZStack(alignment: .topLeading) {
            Text(state.sourceText.isEmpty ? " " : state.sourceText)
                .font(.callout)
                .lineLimit(4)
                .padding(EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0)
            TextEditor(text: $state.sourceText)
                .font(.callout)
                .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: state.sourceText) { onEdit() }
    }

    private var languageBar: some View {
        HStack(spacing: 6) {
            Picker("源语言", selection: $state.sourceLanguage) {
                ForEach(Language.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 108)
            Button(action: onSwap) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.borderless).controlSize(.small).help("交换语言")
            Picker("目标语言", selection: $state.targetLanguage) {
                ForEach(Language.allCases.filter { $0 != .auto }) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 108)
            Spacer()
        }
        .onChange(of: state.sourceLanguage) { onLanguageChange() }
        .onChange(of: state.targetLanguage) { onLanguageChange() }
    }

    @ViewBuilder private var content: some View {
        if let message = state.message {
            Label {
                Text(message).font(.callout)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(.orange)
        } else if state.isTranslating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("翻译中…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { output in resultRow(output) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
        }
    }

    @ViewBuilder private func resultRow(_ output: TranslationOutput) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(output.serviceName).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if output.error == nil {
                    Button { onCopy(output.text) } label: {
                        Image(systemName: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.borderless).help("复制")
                }
            }
            if let error = output.error {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else {
                Text(output.text).font(.callout).textSelection(.enabled)
            }
        }
    }
}
