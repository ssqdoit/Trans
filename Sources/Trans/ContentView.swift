import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: NavigationStore

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < 700 {
                VStack(spacing: 0) {
                    CompactNavigationBar(selection: $navigation.selectedSection)
                    Divider()
                    detailContent
                }
            } else {
                NavigationSplitView {
                    SidebarView(selection: $navigation.selectedSection)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
                } detail: {
                    detailContent
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .background(TransTheme.canvas)
        .background {
            if #available(macOS 15.0, *) {
                AppleTranslationHost()
            }
        }
        .tint(TransTheme.accent)
        .onOpenURL(perform: model.handle)
        .onAppear {
            NSApplication.shared.applicationIconImage = TransBrand.icon
            NSApp.windows
                .filter { !($0 is NSPanel) } // keep the selection popup's own level
                .forEach { $0.level = model.settings.keepOnTop ? .floating : .normal }
        }
        // SwiftUI's built-in localization reads Localizable.strings through
        // the view locale.  Keeping this at the root lets the language picker
        // take effect immediately without restarting the app.
        .environment(
            \.locale,
            (InterfaceLanguage(rawValue: model.settings.interfaceLanguage) ?? .system).locale
        )
        // Recreate localized views when the locale changes. SwiftUI may retain
        // resolved LocalizedStringKey views across an environment-only update.
        .id(model.settings.interfaceLanguage)
    }

    private var detailContent: some View {
        ZStack(alignment: .bottom) {
            // Keep only the active page in the layout tree. Previously every
            // visited page stayed in this ZStack with opacity 0, so resizing
            // the window remeasured all of the heavy pages (OCR, services,
            // plugins, etc.) on every drag event.
            sectionView(navigation.selectedSection)
            if let message = model.statusMessage {
                Text(LocalizedStringKey(message))
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 12, y: 4)
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.statusMessage)
        .background(TransTheme.canvas)
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .translate: TranslationView()
        case .ocr: OCRView()
        case .history: HistoryView()
        case .services: ServicesView()
        case .plugins: PluginsView()
        case .settings: SettingsView()
        }
    }
}

private struct CompactNavigationBar: View {
    @Binding var selection: AppSection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AppSection.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.symbol)
                            Text(LocalizedStringKey(item.rawValue)).font(.system(size: 9))
                        }
                        .frame(minWidth: 52)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == item ? Color.white : Color.secondary)
                    .background(selection == item ? TransTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(TransTheme.sidebar)
    }
}

private struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: TransBrand.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trans").font(.title3.weight(.semibold))
                    Text("随处翻译 · 即见即译").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(AppSection.allCases) { item in
                        Button {
                            selection = item
                        } label: {
                            Label(LocalizedStringKey(item.rawValue), systemImage: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selection == item ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(selection == item ? TransTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("全局快捷键").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                shortcut("text.cursor", "⌥S", "划词翻译")
                shortcut("viewfinder", "⌥D", "截图 OCR")
                shortcut("text.bubble", "⌥A", "输入翻译")
                shortcut("rectangle.dashed.badge.record", "⌥F", "静默 OCR")
                shortcut("rectangle.and.pencil.and.ellipsis", "⌥T", "输入框翻译")
            }
            .padding(14)
            .overlay(alignment: .top) { Divider().padding(.horizontal, 14) }
        }
        .background(TransTheme.sidebar)
    }

    private func shortcut(_ icon: String, _ key: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(title).font(.caption).lineLimit(1)
            Spacer()
            ShortcutKeyLabel(shortcut: key)
        }
        .frame(height: 24)
    }
}

private struct TranslationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "翻译", subtitle: "多服务并发翻译，即用即走") {
                Button { Task { await model.screenshotAndTranslate() } } label: {
                    Label("截图翻译", systemImage: "viewfinder")
                }
                Button { Task { await model.translateSelectionPopup() } } label: {
                    Label("划词翻译", systemImage: "text.cursor")
                }
                .buttonStyle(.bordered)
            }
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        sourceCard
                        if model.isTranslating {
                            ProgressView("正在请求翻译服务…")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        }
                        ForEach(model.outputs) { output in
                            ResultCard(output: output, target: model.targetLanguage)
                        }
                        if model.outputs.isEmpty && !model.isTranslating {
                            EmptyHint(
                                icon: "character.book.closed",
                                title: "开始翻译",
                                detail: "输入文本，或使用 ⌥S 获取任意应用中的选中文字"
                            )
                            .padding(.top, geometry.size.height < 400 ? 4 : 28)
                        }
                    }
                    .padding(geometry.size.width < 600 ? 10 : 24)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { languageControls; Spacer(minLength: 8); sourceMetaControls }
                VStack(spacing: 10) {
                    HStack { languageControls; Spacer(minLength: 0) }
                    HStack { Spacer(minLength: 0); sourceMetaControls }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            TextEditor(text: $model.sourceText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding(12)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.command) {
                        return .ignored
                    }
                    Task { await model.translate() }
                    return .handled
                }
            Divider()
            HStack {
                Button { model.sourceText = NSPasteboard.general.string(forType: .string) ?? "" } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }.buttonStyle(.plain)
                Spacer()
                Button {
                    Task { await model.translate() }
                } label: {
                    Label("翻译", systemImage: "arrow.right.circle.fill")
                        .frame(minWidth: 84)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isTranslating)
            }
            .padding(12)
        }
        .clashCard()
    }

    private var languageControls: some View {
        HStack(spacing: 8) {
            Picker("源语言", selection: $model.sourceLanguage) {
                ForEach(Language.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }.labelsHidden().frame(minWidth: 105, idealWidth: 145, maxWidth: 150)
            Button { model.swapLanguages() } label: { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Picker("目标语言", selection: $model.targetLanguage) {
                ForEach(Language.allCases.filter { $0 != .auto }) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }.labelsHidden().frame(minWidth: 105, idealWidth: 145, maxWidth: 150)
        }
    }

    private var sourceMetaControls: some View {
        HStack(spacing: 10) {
            Text("\(model.sourceText.count) 字符").font(.caption).foregroundStyle(.tertiary)
            Button { model.speak(model.sourceText, language: model.sourceLanguage) } label: {
                Image(systemName: "speaker.wave.2")
            }.buttonStyle(.plain).disabled(model.sourceText.isEmpty)
            Button { model.sourceText = ""; model.outputs = [] } label: {
                Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain).foregroundStyle(.tertiary).disabled(model.sourceText.isEmpty)
        }
    }
}

private struct ResultCard: View {
    @EnvironmentObject private var model: AppModel
    let output: TranslationOutput
    let target: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { resultIdentity; Spacer(minLength: 8); resultMeta }
                VStack(alignment: .leading, spacing: 8) {
                    resultIdentity
                    HStack { Spacer(minLength: 0); resultMeta }
                }
            }
            .padding(14)
            Divider()
            if let error = output.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled).padding(16)
            } else {
                Text(output.text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }
        .padding(.vertical, 10)
        .clashCard()
    }

    private var resultIdentity: some View {
        HStack(spacing: 7) {
            Circle().fill(output.error == nil ? .green : .red).frame(width: 7, height: 7)
            Text(output.serviceName).font(.subheadline.weight(.semibold))
            if let detected = output.detectedLanguage {
                Text("检测：\(detected)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var resultMeta: some View {
        HStack(spacing: 10) {
            Text(String(format: "%.2fs", output.duration)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            if output.error == nil {
                Button { model.speak(output.text, language: target) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.plain)
                Button { model.copy(output.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
            }
        }
    }
}

private struct OCRView: View {
    @EnvironmentObject private var model: AppModel
    private let horizontalBreakpoint: CGFloat = 760

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "文字识别", subtitle: "截图、选图、剪贴板与连续 OCR") {
                Button { Task { await model.chooseAndRecognize() } } label: {
                    Label("选择图片", systemImage: "photo")
                }
                Button { Task { await model.screenshotAndRecognize() } } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "viewfinder")
                        Text("截图识别")
                        ShortcutKeyLabel(shortcut: model.settings.screenshotHotKey, emphasized: true)
                    }
                }
                    .buttonStyle(.borderedProminent)
            }
            Divider()
            inputOptionsBar
            Divider()
            GeometryReader { geometry in
                if model.ocrImage == nil {
                    resultPane
                } else if geometry.size.width >= horizontalBreakpoint {
                    HSplitView {
                        imagePane
                            .frame(minWidth: 280, idealWidth: geometry.size.width * 0.48)
                        resultPane
                            .frame(minWidth: 280, idealWidth: geometry.size.width * 0.52)
                    }
                } else if geometry.size.height >= 420 {
                    VSplitView {
                        imagePane
                            .frame(minHeight: 90, idealHeight: geometry.size.height * 0.48)
                        resultPane
                            .frame(minHeight: 90, idealHeight: geometry.size.height * 0.52)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            imagePane.frame(height: 230)
                            Divider()
                            resultPane.frame(height: 220)
                        }
                    }
                }
            }
        }
    }

    private var imagePane: some View {
        Group {
            if let image = model.ocrImage {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: max(geometry.size.width - 24, 1),
                                height: max(geometry.size.height - 24, 1)
                            )
                            .padding(12)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var resultPane: some View {
        VStack(spacing: 0) {
            resultToolbar
                .padding(12)
            Divider()
            if model.ocrText.isEmpty {
                EmptyHint(
                    icon: "text.viewfinder",
                    title: "开始文字识别",
                    detail: "使用右上角截图或选择图片，也可从剪贴板读取\n支持中英日韩等多语言和二维码"
                )
            } else {
                TextEditor(text: $model.ocrText)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .padding(10)
                if !model.qrCodes.isEmpty {
                    Divider()
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("二维码", systemImage: "qrcode").font(.caption.weight(.semibold))
                            ForEach(model.qrCodes, id: \.self) {
                                Text($0).textSelection(.enabled).font(.caption)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
        }
    }

    private var inputOptionsBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                clipboardButton
                Divider().frame(height: 18)
                continuousToggle
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                clipboardButton
                continuousToggle
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var resultToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack { resultTitle; Spacer(minLength: 8); resultActions }
            VStack(alignment: .leading, spacing: 10) {
                resultTitle
                HStack { Spacer(minLength: 0); resultActions }
            }
        }
    }

    private var resultTitle: some View {
        HStack(spacing: 8) {
            Text("识别结果").font(.headline)
            if !model.ocrBlocks.isEmpty {
                Text("\(model.ocrBlocks.count) 段").font(.caption).foregroundStyle(.secondary)
            }
            if model.isRecognizing { ProgressView().controlSize(.small) }
        }
    }

    private var resultActions: some View {
        HStack(spacing: 10) {
            Button { model.speak(model.ocrText, language: model.sourceLanguage) } label: {
                Image(systemName: "speaker.wave.2")
            }.buttonStyle(.plain).disabled(model.ocrText.isEmpty)
            Button { model.copy(model.ocrText) } label: {
                Image(systemName: "doc.on.doc")
            }.buttonStyle(.plain).disabled(model.ocrText.isEmpty)
            Button("翻译") {
                model.sourceText = model.ocrText
                model.navigation.selectedSection = .translate
                Task { await model.translate(mode: "OCR 翻译") }
            }.disabled(model.ocrText.isEmpty)
        }
    }

    private var clipboardButton: some View {
        Button { Task { await model.recognizeClipboard() } } label: {
            Label("读取剪贴板", systemImage: "doc.on.clipboard")
        }
    }

    private var continuousToggle: some View {
        Toggle("连续识别剪贴板图片", isOn: Binding(
            get: { model.continuousOCR },
            set: { _ in model.toggleContinuousOCR() }
        ))
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ShortcutKeyLabel: View {
    let shortcut: String
    var emphasized = false

    var body: some View {
        Text(shortcut)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(emphasized ? Color.white : Color.secondary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                emphasized ? Color.white.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(emphasized ? Color.white.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.8))
            }
            .accessibilityLabel("快捷键 \(shortcut)")
    }
}

private struct SettingsShortcutRow: View {
    let icon: String
    let title: String
    let shortcut: String
    var emphasized = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(title)
            Spacer()
            ShortcutKeyLabel(shortcut: shortcut)
        }
        .frame(minHeight: 26)
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var favoritesOnly = false

    private var items: [HistoryItem] {
        model.history.filter {
            (!favoritesOnly || $0.isFavorite) &&
            (query.isEmpty || $0.sourceText.localizedCaseInsensitiveContains(query) || $0.outputs.contains { $0.text.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "历史记录", subtitle: "最多保留最近 500 条记录") {
                Toggle("仅收藏", isOn: $favoritesOnly).toggleStyle(.button)
                Button("导出", action: model.exportHistory)
                Button("清空", role: .destructive, action: model.clearHistory).disabled(model.history.isEmpty)
            }
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索原文或译文", text: $query).textFieldStyle(.plain)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(16)
            if items.isEmpty {
                EmptyHint(icon: "clock", title: "没有记录", detail: query.isEmpty ? "完成翻译后会自动保存在这里" : "试试其他关键词")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            HistoryRow(
                                item: item,
                                onToggleFavorite: { model.toggleFavorite(item.id) }
                            )
                            .equatable()
                            .contentShape(Rectangle())
                            .onTapGesture { model.restore(item) }
                            .contextMenu {
                                Button("复制原文") { model.copy(item.sourceText) }
                                Button(item.isFavorite ? "取消收藏" : "收藏") { model.toggleFavorite(item.id) }
                            }
                            Divider()
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

private struct HistoryRow: View, Equatable {
    let item: HistoryItem
    let onToggleFavorite: () -> Void

    static func == (lhs: HistoryRow, rhs: HistoryRow) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.mode.contains("OCR") ? "viewfinder" : "character.book.closed")
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.sourceText).lineLimit(2).font(.body)
                if let result = item.outputs.first(where: { $0.error == nil }) {
                    Text(result.text).lineLimit(2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) { historyMeta }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onToggleFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary.opacity(0.55))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var historyMeta: some View {
        Text(item.mode)
        Text("\(item.sourceLanguage.rawValue) → \(item.targetLanguage.rawValue)")
        Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
    }
}

private enum ServiceCategory: String, CaseIterable, Identifiable {
    case translation = "文本翻译"
    case ocr = "文本识别"
    case speech = "语音合成"
    var id: String { rawValue }
}

private struct ServicesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: ServiceCategory = .translation
    @State private var selectedServiceID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "服务", subtitle: "配置翻译、识别与语音服务。") { EmptyView() }
            Picker("服务类型", selection: $category) {
                ForEach(ServiceCategory.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 600)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            Divider()
            Group {
                switch category {
                case .translation: translationServices
                case .ocr:
                    BuiltInServiceView(
                        title: "离线文本识别",
                        symbol: "text.viewfinder",
                        summary: "基于 macOS Vision 的系统内置文字识别服务，可离线使用。",
                        details: "用于截图翻译、截图 OCR、访达多图 OCR 和剪贴板 OCR。支持自动语言检测、智能分段与二维码识别。"
                    )
                case .speech:
                    BuiltInServiceView(
                        title: "离线语音合成",
                        symbol: "speaker.wave.2.fill",
                        summary: "基于 macOS AVSpeechSynthesizer 的系统内置语音服务。",
                        details: "点击原文或译文旁的朗读按钮时调用。语音和语言由系统根据目标语言自动选择。"
                    )
                }
            }
        }
        .onAppear { ensureSelection() }
        .onChange(of: model.services) { ensureSelection(); model.scheduleServicesSave() }
    }

    private var translationServices: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 520
            let horizontalInset: CGFloat = compact ? 8 : 18
            let availableWidth = geometry.size.width - horizontalInset * 2

            HStack(spacing: 16) {
                serviceList
                    .frame(width: serviceListWidth(for: availableWidth))
                    .clashCard()
                Divider()
                serviceDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clashCard()
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, compact ? 10 : 16)
        }
    }

    private var serviceList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("翻译服务")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.services.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider()
            List(selection: $selectedServiceID) {
                serviceRows
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 0) {
                Menu {
                    ForEach(ServiceKind.allCases.filter { $0 != .plugin }, id: \.self) { kind in
                        Button(LocalizedStringKey(kind.rawValue)) { selectedServiceID = model.addService(kind: kind) }
                    }
                } label: {
                    Label("添加", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity)
                .help("添加翻译服务")
                Divider().frame(height: 24)
                Button {
                    if let id = selectedServiceID {
                        model.removeService(id)
                        selectedServiceID = model.services.first?.id
                    }
                } label: {
                    Label("删除", systemImage: "minus")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(selectedServiceID == nil)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
        }
        .background(TransTheme.card)
    }

    private func serviceListWidth(for containerWidth: CGFloat) -> CGFloat {
        min(300, max(180, containerWidth * 0.34))
    }

    private var serviceRows: some View {
        ForEach($model.services) { $service in
            ServiceListRow(service: $service, selected: selectedServiceID == service.id)
                .tag(service.id)
        }
    }

    @ViewBuilder private var serviceDetail: some View {
        if let id = selectedServiceID,
           let index = model.services.firstIndex(where: { $0.id == id }) {
            ScrollView {
                ServiceEditor(service: $model.services[index]) {
                    model.removeService(id)
                    selectedServiceID = model.services.first?.id
                } moveUp: {
                    model.moveService(id, offset: -1)
                } moveDown: {
                    model.moveService(id, offset: 1)
                } validate: {
                    Task { await model.validateService(id) }
                }
                .environmentObject(model)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        } else {
            EmptyHint(icon: "square.stack.3d.up", title: "选择服务", detail: "从左侧选择服务查看配置")
        }
    }

    private func ensureSelection() {
        if selectedServiceID == nil || !model.services.contains(where: { $0.id == selectedServiceID }) {
            selectedServiceID = model.services.first?.id
        }
    }
}

private struct ServiceListRow: View {
    @Binding var service: TranslationServiceConfig
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: serviceSymbol(service.kind))
                .font(.body)
                .foregroundStyle(selected ? Color.white.opacity(0.92) : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .lineLimit(1)
                    .font(.subheadline.weight(.medium))
                Text(LocalizedStringKey(serviceBadge(service.kind)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.82) : (service.kind == .appleLocal ? Color.green : Color.accentColor))
            }
            Spacer(minLength: 6)
            Toggle("启用", isOn: $service.enabled).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        // Let List provide the single system selection highlight. A second
        // row background here creates the pale outer rectangle seen around
        // selected services.
        .listRowBackground(Color.clear)
    }
}

private struct BuiltInServiceView: View {
    let title: String
    let symbol: String
    let summary: String
    let details: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 12)
                    Text("内置")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.1), in: Capsule())
                    Toggle("启用", isOn: .constant(true))
                        .labelsHidden()
                        .controlSize(.small)
                }
                Divider().padding(.top, 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary)
                        .font(.body.weight(.medium))
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 18)
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .clashCard()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(18)
        }
        .background(TransTheme.canvas)
    }
}

private func serviceBadge(_ kind: ServiceKind) -> String {
    switch kind {
    case .appleLocal: "内置"
    case .ollama: "本地"
    case .google, .microsoft: "公共"
    case .libre: "可选"
    default: "密钥"
    }
}

private func serviceSymbol(_ kind: ServiceKind) -> String {
    switch kind {
    case .appleLocal: "apple.logo"
    case .google: "g.circle.fill"
    case .microsoft: "square.grid.2x2.fill"
    case .baidu: "b.circle.fill"
    case .youdao: "y.circle.fill"
    case .caiyun: "cloud.sun.fill"
    case .niu: "n.circle.fill"
    case .openAI: "sparkles"
    case .ollama: "cube.transparent"
    case .qwen: "q.circle.fill"
    case .deepseek: "d.circle.fill"
    case .kimi: "k.circle.fill"
    case .glm: "z.circle.fill"
    case .deepL: "character.bubble"
    case .libre: "globe"
    case .plugin: "puzzlepiece"
    }
}

private struct ServiceEditor: View {
    @Binding var service: TranslationServiceConfig
    var remove: () -> Void
    var moveUp: () -> Void
    var moveDown: () -> Void
    var validate: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { serviceIdentity; Spacer(minLength: 8); serviceActions }
                VStack(alignment: .leading, spacing: 10) {
                    serviceIdentity
                    HStack { Spacer(minLength: 0); serviceActions }
                }
            }.padding(14)
            Divider()
            ViewThatFits(in: .horizontal) {
                wideConfiguration
                compactConfiguration
            }
            .padding(14)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { validationStatus; serviceFooterText; Spacer(); validateButton; removeButton }
                VStack(alignment: .leading, spacing: 8) { validationStatus; serviceFooterText; HStack { validateButton; removeButton } }
            }.padding(12)
        }
        .padding(.vertical, 8)
        .clashCard()
    }
    private var serviceIdentity: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                TextField("服务名称", text: $service.name).font(.headline).textFieldStyle(.plain)
                Text(LocalizedStringKey(service.kind.rawValue)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var serviceActions: some View {
        HStack(spacing: 12) {
            Button(action: moveUp) { Image(systemName: "arrow.up") }.buttonStyle(.plain).help("上移")
            Button(action: moveDown) { Image(systemName: "arrow.down") }.buttonStyle(.plain).help("下移")
            Toggle("启用", isOn: $service.enabled).labelsHidden()
        }
    }
    private var wideConfiguration: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            if service.kind != .appleLocal {
                GridRow { configurationLabel("接口地址"); TextField("https://…", text: $service.endpoint) }
            }
            if needsPrimaryCredential {
                GridRow { configurationLabel(primaryCredentialLabel); SecureField(credentialPlaceholder, text: $service.apiKey) }
            }
            if needsSecondarySecret {
                GridRow { configurationLabel(secondaryCredentialLabel); secondarySecretField }
            }
            if service.kind.usesOpenAIProtocol {
                GridRow { configurationLabel("模型"); TextField(service.kind.defaultModel, text: $service.model) }
            }
            if service.kind == .microsoft {
                GridRow { configurationLabel("Azure 区域"); regionField }
            }
            if service.kind == .appleLocal {
                GridRow { configurationLabel("说明"); builtInServiceNote }
            }
        }
    }
    private var compactConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.kind != .appleLocal {
                configurationField("接口地址") { TextField("https://…", text: $service.endpoint) }
            }
            if needsPrimaryCredential {
                configurationField(primaryCredentialLabel) { SecureField(credentialPlaceholder, text: $service.apiKey) }
            }
            if needsSecondarySecret {
                configurationField(secondaryCredentialLabel) { secondarySecretField }
            }
            if service.kind.usesOpenAIProtocol {
                configurationField("模型") { TextField(service.kind.defaultModel, text: $service.model) }
            }
            if service.kind == .microsoft {
                configurationField("Azure 区域") { regionField }
            }
            if service.kind == .appleLocal {
                configurationField("说明") { builtInServiceNote }
            }
        }
    }
    private var secondarySecretField: some View {
        SecureField("必填", text: Binding(
            get: { service.secretKey ?? "" },
            set: { service.secretKey = $0 }
        ))
    }
    private var regionField: some View {
        TextField("公共模式留空；例如 eastasia", text: Binding(
            get: { service.region ?? "" },
            set: { service.region = $0 }
        ))
    }
    private var builtInServiceNote: some View {
        Text("系统内置离线翻译，无需任何配置。首次使用某个语言组合时，系统会自动提示下载语言包。")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
    private func configurationLabel(_ title: String) -> some View {
        Text(title).foregroundStyle(.secondary)
    }
    private func configurationField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            configurationLabel(title).font(.caption)
            content()
        }
    }
    private var serviceFooterText: some View {
        Text(service.kind == .appleLocal ? "系统内置服务，无需密钥" : "密钥安全保存在 macOS 钥匙串")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    private var removeButton: some View {
        Button("删除服务", role: .destructive, action: remove)
    }
    private var validateButton: some View {
        Button("验证", action: validate)
    }
    @ViewBuilder private var validationStatus: some View {
        if let status = model.serviceValidation[service.id] {
            Text(status).font(.caption).foregroundStyle(status.contains("成功") ? Color.green : Color.orange)
        }
    }
    private var needsPrimaryCredential: Bool {
        service.kind != .google && service.kind != .appleLocal && service.kind != .ollama
    }
    private var needsSecondarySecret: Bool { service.kind == .baidu || service.kind == .youdao }
    private var credentialPlaceholder: String { service.kind == .microsoft ? "公共模式可留空" : "必填" }
    private var primaryCredentialLabel: String {
        switch service.kind {
        case .baidu: "App ID"
        case .youdao: "App Key"
        case .caiyun: "Token"
        default: "API Key"
        }
    }
    private var secondaryCredentialLabel: String { service.kind == .baidu ? "Secret Key" : "App Secret" }
    private var icon: String {
        switch service.kind {
        case .appleLocal: "apple.logo"
        case .google: "g.circle.fill"
        case .microsoft: "square.grid.2x2.fill"
        case .baidu: "b.circle.fill"
        case .youdao: "y.circle.fill"
        case .caiyun: "cloud.sun.fill"
        case .niu: "n.circle.fill"
        case .openAI: "sparkles"
        case .ollama: "cube.transparent"
        case .qwen: "q.circle.fill"
        case .deepseek: "d.circle.fill"
        case .kimi: "k.circle.fill"
        case .glm: "z.circle.fill"
        case .deepL: "character.bubble"
        case .libre: "globe"
        case .plugin: "puzzlepiece"
        }
    }
}

private struct PluginsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expandedConfigurations: Set<String> = []
    @State private var expandedGuides: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "插件", subtitle: "兼容 Trans 文本翻译插件，并提供可直接使用的内置工具") {
                Button(action: model.installPlugin) {
                    Label("导入插件", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            if model.plugins.isEmpty {
                EmptyHint(
                    icon: "puzzlepiece.extension",
                    title: "尚未安装插件",
                    detail: "可导入 .zip、.zip，或选择包含 manifest.json 与 main.js 的目录"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($model.plugins) { $plugin in
                            pluginCard($plugin)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.plugins) { model.schedulePluginsSave() }
                .safeAreaInset(edge: .bottom) {
                    Text("第三方插件会执行 JavaScript 并可访问网络，请只导入可信来源的插件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
        }
    }

    private func pluginCard(_ plugin: Binding<InstalledPlugin>) -> some View {
        let id = plugin.wrappedValue.id
        let configurationIsExpanded = expandedConfigurations.contains(id)
        let guideIsExpanded = expandedGuides.contains(id)

        return VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    pluginIdentity(plugin.wrappedValue)
                    Spacer(minLength: 12)
                    pluginActions(plugin)
                }
                VStack(alignment: .leading, spacing: 12) {
                    pluginIdentity(plugin.wrappedValue)
                    HStack { Spacer(minLength: 0); pluginActions(plugin) }
                }
            }

            HStack(spacing: 8) {
                if !plugin.wrappedValue.options.isEmpty {
                    pluginDetailButton(
                        title: "插件配置",
                        systemImage: "slider.horizontal.3",
                        isExpanded: configurationIsExpanded
                    ) {
                        toggle(&expandedConfigurations, id: id)
                    }
                }
                if plugin.wrappedValue.source == .builtIn {
                    pluginDetailButton(
                        title: "使用说明",
                        systemImage: "book.pages",
                        isExpanded: guideIsExpanded
                    ) {
                        toggle(&expandedGuides, id: id)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            if configurationIsExpanded {
                Divider().padding(.top, 14)
                VStack(alignment: .leading, spacing: 12) {
                    Text("插件配置")
                        .font(.subheadline.weight(.semibold))
                    ForEach(plugin.wrappedValue.options) { option in
                        optionEditor(plugin: plugin, option: option)
                    }
                }
                .padding(.top, 14)
            }

            if guideIsExpanded {
                Divider().padding(.top, 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text("使用说明")
                        .font(.subheadline.weight(.semibold))
                        .padding(.bottom, 10)
                    pluginGuide(plugin.wrappedValue)
                }
                .padding(.top, 14)
            }

            if !plugin.wrappedValue.category.isSupported {
                Label(
                    "已导入，但 Trans 当前尚未接入 Trans \(plugin.wrappedValue.category.displayName) 插件",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 14)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func pluginDetailButton(
        title: String,
        systemImage: String,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(isExpanded ? Color.white : Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isExpanded ? Color.accentColor : Color.accentColor.opacity(0.1),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "收起\(title)" : "查看\(title)")
    }

    private func toggle(_ set: inout Set<String>, id: String) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func pluginIdentity(_ plugin: InstalledPlugin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(plugin.name).font(.headline)
                    Text("v\(plugin.version)").font(.caption).foregroundStyle(.secondary)
                    pluginBadge(plugin.source.displayName, color: plugin.source == .builtIn ? .green : .blue)
                    pluginBadge(plugin.category.displayName, color: plugin.category.isSupported ? .purple : .orange)
                }
                if let summary = plugin.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let author = plugin.author { Text(author).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }

    private func pluginActions(_ plugin: Binding<InstalledPlugin>) -> some View {
        HStack(spacing: 12) {
            Toggle("启用", isOn: plugin.enabled)
                .labelsHidden()
                .disabled(!plugin.wrappedValue.category.isSupported)
                .help(plugin.wrappedValue.enabled ? "关闭插件" : "开启插件")
            Menu {
                if plugin.wrappedValue.homepage != nil {
                    Button("打开插件主页") { model.openPluginHomepage(plugin.wrappedValue) }
                }
                if !plugin.wrappedValue.options.isEmpty {
                    Button("重置配置") { model.resetPluginConfiguration(plugin.wrappedValue) }
                }
                if plugin.wrappedValue.source != .builtIn {
                    Divider()
                    Button("卸载", role: .destructive) { model.uninstallPlugin(plugin.wrappedValue) }
                } else {
                    Divider()
                    Text("内置插件不可卸载")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func optionEditor(plugin: Binding<InstalledPlugin>, option: PluginOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(option.title).font(.caption.weight(.medium))
            if option.type == "menu", let values = option.menuValues, !values.isEmpty {
                Picker(option.title, selection: optionBinding(plugin: plugin, option: option)) {
                    ForEach(values) { value in Text(value.title).tag(value.value) }
                }
                .labelsHidden()
                .frame(maxWidth: 360, alignment: .leading)
            } else if option.isSecure {
                SecureField(
                    option.textConfig?.placeholderText ?? option.title,
                    text: optionBinding(plugin: plugin, option: option)
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)
            } else if (option.textConfig?.height ?? 0) > 40 {
                TextEditor(text: optionBinding(plugin: plugin, option: option))
                    .font(.body)
                    .frame(minHeight: option.textConfig?.height ?? 64, maxHeight: 120)
                    .padding(5)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            } else {
                TextField(
                    option.textConfig?.placeholderText ?? option.title,
                    text: optionBinding(plugin: plugin, option: option)
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)
            }
            if let description = option.desc, !description.isEmpty {
                Text(description).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func optionBinding(
        plugin: Binding<InstalledPlugin>,
        option: PluginOption
    ) -> Binding<String> {
        Binding(
            get: { plugin.wrappedValue.optionValues[option.identifier] ?? option.defaultValue ?? "" },
            set: { plugin.wrappedValue.optionValues[option.identifier] = $0 }
        )
    }

    private func pluginBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private func pluginGuide(_ plugin: InstalledPlugin) -> some View {
        switch plugin.identifier {
        case "com.trans.builtin.chinese-tools":
            guideBlock(
                title: "把中文转换成另一种形式",
                steps: [
                    "开启插件后，在“插件配置”中选择简体转繁体、繁体转简体，或带/不带声调拼音。",
                    "在翻译输入框、划词翻译或 OCR 结果中使用，输出会和其他已开启服务并列显示。"
                ],
                effect: "例如：繁體中文 → 繁体中文；你好 → nǐ hǎo（带声调拼音）。"
            )
        case "com.trans.builtin.text-tools":
            guideBlock(
                title: "对选中文本做快速格式处理",
                steps: [
                    "在“插件配置”中选择清理空白、格式化 JSON、URL 编解码、大小写或代码命名转换。",
                    "把要处理的文本放入输入翻译框，或使用划词翻译；它不会访问网络。"
                ],
                effect: "例如：helloWorld → hello_world；多余空格和连续空行会被清理。"
            )
        case "com.trans.builtin.ai-writer":
            guideBlock(
                title: "用 OpenAI 兼容模型处理文本",
                steps: [
                    "填写接口地址、API Key 和模型；兼容 OpenAI Chat Completions 的服务通常可以直接使用。",
                    "选择翻译、润色、语法纠错、解释或自定义指令，然后开启插件。",
                    "API Key 只保存在 macOS 钥匙串；请求会发送到你填写的接口地址。"
                ],
                effect: "适合论文润色、邮件改写、语法修正和按自定义规则翻译。"
            )
        default:
            Text(plugin.summary ?? "开启后会参与文本翻译，并在结果列表中显示输出。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func guideBlock(title: String, steps: [String], effect: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Label(step, systemImage: "(index + 1).circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label {
                Text(effect)
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Header(title: "设置", subtitle: "调整 Trans 的工作方式") { EmptyView() }
            Divider()
            Form {
                Section("外观与语言") {
                    Picker("界面语言", selection: $model.settings.interfaceLanguage) {
                        ForEach(InterfaceLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.rawValue)).tag(language.rawValue)
                        }
                    }
                    Picker("外观", selection: Binding(
                        get: { model.settings.colorScheme },
                        set: { model.setColorScheme($0) }
                    )) {
                        ForEach(ColorSchemePreference.allCases) { preference in
                            Text(LocalizedStringKey(preference.rawValue)).tag(preference.rawValue)
                        }
                    }
                }
                Section("翻译与识别") {
                    Toggle("OCR 后自动复制文本", isOn: $model.settings.copyAfterOCR)
                    Toggle("OCR 后自动翻译", isOn: $model.settings.autoTranslate)
                    Toggle("OCR 智能分段", isOn: $model.settings.smartParagraphs)
                }
                Section("划词翻译") {
                    Toggle("划词后自动弹出翻译小窗", isOn: Binding(
                        get: { model.settings.selectionPopupEnabled },
                        set: { model.setSelectionPopupEnabled($0) }
                    ))
                    Text("在其他应用中拖选或双击文字后自动取词并在光标旁显示翻译；需要辅助功能权限。个别应用不支持辅助功能取词，可改用 \(model.settings.selectionHotKey) 热键。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("窗口") {
                    Toggle("登录时启动", isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Toggle("窗口始终置顶", isOn: $model.settings.keepOnTop)
                    Toggle("记住窗口位置", isOn: $model.settings.rememberWindow)
                }
                Section("快捷键") {
                    SettingsShortcutRow(icon: "text.cursor", title: "划词翻译", shortcut: model.settings.selectionHotKey)
                    SettingsShortcutRow(icon: "viewfinder", title: "截图 OCR", shortcut: model.settings.screenshotHotKey, emphasized: true)
                    SettingsShortcutRow(icon: "text.bubble", title: "输入翻译", shortcut: model.settings.inputHotKey)
                    SettingsShortcutRow(icon: "rectangle.dashed.badge.record", title: "静默 OCR", shortcut: model.settings.ocrHotKey)
                    SettingsShortcutRow(icon: "rectangle.and.pencil.and.ellipsis", title: "输入框翻译", shortcut: model.settings.inputBoxHotKey)
                    Text("全局快捷键由系统热键注册；划词读取和输入框替换需要“辅助功能”权限。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let warning = model.hotKeyWarning {
                        Text(warning).font(.caption).foregroundStyle(.orange)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { permissionTestButton; permissionTestResult }
                        VStack(alignment: .leading, spacing: 8) {
                            permissionTestButton
                            permissionTestResult
                        }
                    }
                }
                Section("数据与隐私") {
                    Text("翻译文本仅发送到你启用的服务。历史、服务配置和插件均存储在本机。")
                        .foregroundStyle(.secondary)
                    Button("导出历史记录", action: model.exportHistory)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 700)
            .onChange(of: model.settings) { _, value in
                model.scheduleSettingsSave()
                NSApp.windows
                    .filter { !($0 is NSPanel) }
                    .forEach { $0.level = value.keepOnTop ? .floating : .normal }
            }
        }
    }

    private var permissionTestButton: some View {
        Button("运行权限自测") { Task { await model.runPermissionSelfTest() } }
    }

    @ViewBuilder private var permissionTestResult: some View {
        if let result = model.permissionTestResult {
            Text(result).font(.caption).foregroundStyle(
                result.contains("通过") ? Color.green : Color.orange
            )
        }
    }
}

private struct Header<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                titleBlock
                Spacer(minLength: 16)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                HStack { actions }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
        .background(TransTheme.header)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct EmptyHint: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 36, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(34)
    }
}

private enum TransTheme {
    static let accent = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let header = Color(nsColor: .controlBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.45)
}

private extension View {
    func clashCard() -> some View {
        background(TransTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(TransTheme.border)
            }
    }
}
