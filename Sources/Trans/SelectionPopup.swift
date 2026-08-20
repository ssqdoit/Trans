import AppKit
import SwiftUI

enum SelectionPopupKind {
    case translation
    case ocr
}

@MainActor
final class SelectionPopupState: ObservableObject {
    @Published var title = "划词翻译"
    @Published var sourceText = ""
    @Published var outputs: [TranslationOutput] = []
    @Published var isTranslating = false
    @Published var message: String?
    @Published var sourceLanguage: Language = .auto
    @Published var targetLanguage: Language = .zhHans
    @Published var isPinned = false
    @Published var kind: SelectionPopupKind = .translation
}

/// Borderless panel that can take key status for in-popup interaction without
/// activating Trans (.nonactivatingPanel keeps the source app frontmost).
private final class SelectionPopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SelectionPopupController {
    static let panelWidth: CGFloat = 408
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
    /// The text this session was opened with; unlike lastShownText it is not
    /// rewritten by in-popup edits, so it still matches the AX selection.
    private(set) var sessionSelectionText: String?
    private(set) var dismissedText: String?
    private(set) var sessionID = UUID()

    var isVisible: Bool { panel?.isVisible ?? false }

    @discardableResult
    func show(
        text: String,
        title: String = "划词翻译",
        kind: SelectionPopupKind = .translation,
        source: Language,
        target: Language,
        at mouse: CGPoint
    ) -> UUID {
        editDebounceTask?.cancel()
        removeDismissMonitors()
        sessionID = UUID()
        dismissedText = nil
        state.title = title
        state.kind = kind
        state.sourceText = text
        state.sourceLanguage = source
        state.targetLanguage = target
        state.outputs = []
        state.message = nil
        state.isTranslating = true
        lastShownText = text
        sessionSelectionText = text
        lastMouse = mouse
        presentAfterLayout()
        return sessionID
    }

    func showMessage(
        _ message: String,
        title: String = "划词翻译",
        kind: SelectionPopupKind = .translation,
        at mouse: CGPoint
    ) {
        editDebounceTask?.cancel()
        removeDismissMonitors()
        sessionID = UUID()
        dismissedText = nil
        state.title = title
        state.kind = kind
        state.sourceText = ""
        state.outputs = []
        state.isTranslating = false
        state.message = message
        lastShownText = nil
        sessionSelectionText = nil
        lastMouse = mouse
        presentAfterLayout()
    }

    /// Marks a retranslation in flight (edit or language change) without
    /// resetting the shown text or reopening the panel at a new location.
    @discardableResult
    func beginTranslating() -> UUID {
        sessionID = UUID()
        state.message = nil
        state.isTranslating = true
        if isVisible { presentAfterLayout() }
        return sessionID
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

    /// `suppressingReshow` marks an explicit close (✕ button, Esc/⌘W, open in
    /// main window): the still-selected source text must not auto-reopen the
    /// popup on the next drag gesture.
    func dismiss(suppressingReshow: Bool = false) {
        editDebounceTask?.cancel()
        sessionID = UUID()
        dismissedText = suppressingReshow ? sessionSelectionText : nil
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

    fileprivate func togglePinned() {
        state.isPinned.toggle()
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
            if panel.isVisible {
                // The user may have dragged the panel; resize in place instead
                // of snapping back to the mouse-anchored position.
                let screen = panel.screen?.visibleFrame ?? Self.screenFrame(containing: panel.frame.origin)
                let origin = PopupPlacement.anchoredOrigin(currentFrame: panel.frame, newSize: size, screen: screen)
                panel.setFrame(CGRect(origin: origin, size: size), display: true)
            } else {
                let screen = Self.screenFrame(containing: lastMouse)
                let origin = PopupPlacement.origin(mouse: lastMouse, panelSize: size, screen: screen)
                panel.setFrame(CGRect(origin: origin, size: size), display: true)
                panel.orderFrontRegardless()
            }
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
                self?.dismiss(suppressingReshow: true)
            },
            onClose: { [weak self] in self?.dismiss(suppressingReshow: true) },
            onTogglePin: { [weak self] in self?.togglePinned() },
            onRetry: { [weak self] in
                guard let self else { return }
                self.onRetranslate?(self.state.sourceText)
            },
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
        panel.animationBehavior = .utilityWindow
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
                Task { @MainActor in
                    guard let self, !self.state.isPinned else { return }
                    self.dismiss()
                }
            }
        )
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self else { return event }
                let inPopup = event.window is SelectionPopupPanel
                if event.type == .keyDown {
                    guard inPopup else { return event }
                    let command = event.modifierFlags.contains(.command)
                    switch (event.charactersIgnoringModifiers?.lowercased(), command, event.keyCode) {
                    case (_, _, 53), ("w", true, _):
                        Task { @MainActor in self.dismiss(suppressingReshow: true) }
                        return nil
                    case ("p", true, _):
                        self.togglePinned()
                        return nil
                    case ("r", true, _):
                        self.onRetranslate?(self.state.sourceText)
                        return nil
                    default:
                        return event
                    }
                }
                if !inPopup, !state.isPinned { Task { @MainActor in self.dismiss() } }
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
    var onTogglePin: () -> Void
    var onRetry: () -> Void
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
        VStack(alignment: .leading, spacing: 10) {
            header
            if hasSession {
                sourceCard
                languageBar
            }
            content
        }
        .padding(10)
        .frame(width: SelectionPopupController.panelWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(headerAccent.opacity(0.14))
                Image(systemName: state.kind == .ocr ? "viewfinder" : "character.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(headerAccent)
            }
            .frame(width: 24, height: 24)
            popupButton(
                systemName: state.isPinned ? "pin.fill" : "pin",
                help: state.isPinned ? "取消钉住（⌘P）" : "钉住窗口（⌘P）",
                action: onTogglePin
            )
            .foregroundStyle(state.isPinned ? Color.accentColor : Color.secondary)
            Text(state.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            popupButton(systemName: "arrow.clockwise", help: "重新翻译（⌘R）") {
                onRetry()
            }
            .disabled(state.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            popupButton(systemName: "macwindow", help: "在主窗口中打开", action: onOpenMain)
            popupButton(systemName: "xmark", help: "关闭（⌘W / Esc）", action: onClose)
                .foregroundStyle(.secondary)
        }
    }

    private var headerAccent: Color {
        state.kind == .ocr ? Color(red: 0.09, green: 0.55, blue: 0.65) : .accentColor
    }

    private func popupButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.medium))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(state.kind == .ocr ? "识别文本" : "原文")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { onCopy(state.sourceText) } label: {
                    Image(systemName: "doc.on.doc").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("复制原文")
            }
            sourceEditor
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private var sourceEditorHeight: CGFloat {
        let estimatedLines = state.sourceText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { total, line in total + max(1, (line.count + 27) / 28) }
        let visibleLines = min(max(estimatedLines, 1), 4)
        return max(CGFloat(visibleLines) * 19 + 12, 42)
    }

    /// Editable source text, auto-sizing up to four lines and scrolling beyond it.
    private var sourceEditor: some View {
        TextEditor(text: $state.sourceText)
            .font(.callout)
            .scrollContentBackground(.hidden)
            .padding(-4)
            .frame(height: sourceEditorHeight)
        .onChange(of: state.sourceText) { onEdit() }
    }

    private var languageBar: some View {
        HStack(spacing: 8) {
            Picker("源语言", selection: $state.sourceLanguage) {
                ForEach(Language.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 126)
            Button(action: onSwap) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.plain).controlSize(.small).foregroundStyle(.secondary).help("交换语言")
            Picker("目标语言", selection: $state.targetLanguage) {
                ForEach(Language.allCases.filter { $0 != .auto }) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 126)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        } else if state.isTranslating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(state.kind == .ocr ? "正在整理翻译结果…" : "翻译中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { output in resultRow(output) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
        }
    }

    @ViewBuilder private func resultRow(_ output: TranslationOutput) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(output.error == nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(output.serviceName).font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }
}
