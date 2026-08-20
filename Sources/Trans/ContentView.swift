import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < 700 {
                VStack(spacing: 0) {
                    CompactNavigationBar(selection: $model.selectedSection)
                    Divider()
                    detailContent
                }
            } else {
                NavigationSplitView {
                    SidebarView(selection: $model.selectedSection)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
                } detail: {
                    detailContent
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .background {
            if #available(macOS 15.0, *) {
                AppleTranslationHost()
            }
        }
        .onOpenURL(perform: model.handle)
        .onAppear {
            NSApp.windows
                .filter { !($0 is NSPanel) } // keep the selection popup's own level
                .forEach { $0.level = model.settings.keepOnTop ? .floating : .normal }
        }
    }

    private var detailContent: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch model.selectedSection {
                case .translate: TranslationView()
                case .ocr: OCRView()
                case .history: HistoryView()
                case .services: ServicesView()
                case .plugins: PluginsView()
                case .settings: SettingsView()
                }
            }
            if let message = model.statusMessage {
                Text(message)
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
                            Text(item.rawValue).font(.system(size: 9))
                        }
                        .frame(minWidth: 52)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == item ? Color.accentColor : Color.secondary)
                    .background(selection == item ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(.thinMaterial)
    }
}

private struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
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

            List(AppSection.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
                    .padding(.vertical, 4)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 6) {
                Text("全局快捷键").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                shortcut("text.cursor", "⌥S", "划词翻译")
                shortcut("viewfinder", "⌥D", "截图 OCR")
                shortcut("text.bubble", "⌥A", "输入翻译")
                shortcut("rectangle.dashed.badge.record", "⌥F", "静默 OCR")
                shortcut("rectangle.and.pencil.and.ellipsis", "⌥T", "输入框翻译")
            }
            .padding(16)
        }
        .background(.thinMaterial)
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
                            ProgressView("正在请求翻译服务…").frame(maxWidth: .infinity).padding(30)
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
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.7)))
    }

    private var languageControls: some View {
        HStack(spacing: 8) {
            Picker("源语言", selection: $model.sourceLanguage) {
                ForEach(Language.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(minWidth: 105, idealWidth: 145, maxWidth: 150)
            Button { model.swapLanguages() } label: { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Picker("目标语言", selection: $model.targetLanguage) {
                ForEach(Language.allCases.filter { $0 != .auto }) { Text($0.rawValue).tag($0) }
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
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.7)))
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
            GeometryReader { geometry in
                if geometry.size.width >= horizontalBreakpoint {
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
        VStack(spacing: 12) {
            Group {
                if let image = model.ocrImage {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(geometry.size.width - 20, 1),
                                    height: max(geometry.size.height - 20, 1)
                                )
                                .padding(10)
                        }
                    }
                } else {
                    OCRCapturePlaceholder(
                        shortcut: model.settings.screenshotHotKey,
                        onCapture: { Task { await model.screenshotAndRecognize() } },
                        onChoose: { Task { await model.chooseAndRecognize() } }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            ViewThatFits(in: .horizontal) {
                HStack {
                    clipboardButton
                    continuousToggle
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    clipboardButton
                    continuousToggle
                }
            }
        }
        .padding(14)
    }

    private var resultPane: some View {
        VStack(spacing: 0) {
            resultToolbar
                .padding(12)
            Divider()
            if model.ocrText.isEmpty {
                EmptyHint(icon: "text.viewfinder", title: "等待识别", detail: "支持中英日韩等多语言和二维码")
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
                model.selectedSection = .translate
                Task { await model.translate(mode: "OCR 翻译") }
            }.disabled(model.ocrText.isEmpty)
        }
    }

    private var clipboardButton: some View {
        Button("读取剪贴板") { Task { await model.recognizeClipboard() } }
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

private struct OCRCapturePlaceholder: View {
    let shortcut: String
    let onCapture: () -> Void
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.09, green: 0.55, blue: 0.65).opacity(0.12))
                Image(systemName: "viewfinder")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color(red: 0.09, green: 0.55, blue: 0.65))
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 3) {
                Text("截图识别").font(.headline)
                Text("框选屏幕内容").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: onCapture) {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                        Text("截图")
                        ShortcutKeyLabel(shortcut: shortcut, emphasized: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button(action: onChoose) {
                    Image(systemName: "photo")
                }
                .buttonStyle(.bordered)
                .help("选择图片")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
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
                .foregroundStyle(emphasized ? Color(red: 0.09, green: 0.55, blue: 0.65) : Color.secondary)
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
            .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9)).padding(16)
            if items.isEmpty {
                EmptyHint(icon: "clock", title: "没有记录", detail: query.isEmpty ? "完成翻译后会自动保存在这里" : "试试其他关键词")
            } else {
                List(items) { item in
                    HistoryRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { model.restore(item) }
                        .contextMenu {
                            Button("复制原文") { model.copy(item.sourceText) }
                            Button(item.isFavorite ? "取消收藏" : "收藏") { model.toggleFavorite(item.id) }
                        }
                }.listStyle(.inset)
            }
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    let item: HistoryItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.mode.contains("OCR") ? "viewfinder" : "character.book.closed")
                .frame(width: 28, height: 28).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.sourceText).lineLimit(2).font(.body)
                if let result = item.outputs.first(where: { $0.error == nil }) {
                    Text(result.text).lineLimit(2).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { historyMeta }
                    VStack(alignment: .leading, spacing: 2) { historyMeta }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button { model.toggleFavorite(item.id) } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary.opacity(0.55))
            }.buttonStyle(.plain)
        }.padding(.vertical, 7)
    }

    @ViewBuilder private var historyMeta: some View {
        Text(item.mode)
        Text("\(item.sourceLanguage.rawValue) → \(item.targetLanguage.rawValue)")
        Text(item.createdAt, style: .relative)
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
            Header(title: "服务", subtitle: "翻译功能的核心服务支持配置，开启的服务将被使用。") { EmptyView() }
            Picker("服务类型", selection: $category) {
                ForEach(ServiceCategory.allCases) { Text($0.rawValue).tag($0) }
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
        .onChange(of: model.services) { ensureSelection(); model.saveServices() }
    }

    private var translationServices: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 520
            let horizontalInset: CGFloat = compact ? 10 : 18
            let paneSpacing: CGFloat = compact ? 10 : 16
            let availableWidth = geometry.size.width - horizontalInset * 2 - paneSpacing

            HStack(spacing: paneSpacing) {
                serviceList
                    .frame(width: serviceListWidth(for: availableWidth))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator.opacity(0.7))
                    }
                serviceDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, compact ? 10 : 14)
            .padding(.bottom, compact ? 10 : 18)
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
            ScrollView {
                LazyVStack(spacing: 3) {
                    serviceRows
                }
                .padding(8)
            }
            Divider()
            HStack(spacing: 0) {
                Menu {
                    ForEach(ServiceKind.allCases.filter { $0 != .plugin }, id: \.self) { kind in
                        Button(kind.rawValue) { selectedServiceID = model.addService(kind: kind) }
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
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func serviceListWidth(for containerWidth: CGFloat) -> CGFloat {
        min(300, max(180, containerWidth * 0.34))
    }

    private var serviceRows: some View {
        ForEach($model.services) { $service in
            ServiceListRow(service: $service, selected: selectedServiceID == service.id)
                .contentShape(Rectangle())
                .onTapGesture { selectedServiceID = service.id }
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
                .font(.body).foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .lineLimit(1)
                    .font(.subheadline.weight(.medium))
                Text(serviceBadge(service.kind))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(service.kind == .appleLocal ? .green : .blue)
            }
            Spacer(minLength: 6)
            Toggle("启用", isOn: $service.enabled).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(selected ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct BuiltInServiceView: View {
    let title: String
    let symbol: String
    let summary: String
    let details: String

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 650 {
                HSplitView { listPane.frame(minWidth: 250, idealWidth: 310); detailPane.frame(minWidth: 330) }
            } else {
                VStack(spacing: 0) { listPane.frame(height: 90); Divider(); detailPane }
            }
        }
    }

    private var listPane: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.blue).frame(width: 34, height: 34).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                Text(title).font(.headline)
                Spacer()
                Text("内置").font(.caption2.weight(.semibold)).foregroundStyle(.green).padding(.horizontal, 7).padding(.vertical, 3).background(.green.opacity(0.1), in: Capsule())
                Toggle("启用", isOn: .constant(true)).labelsHidden().controlSize(.small)
            }
            .padding(12)
            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol).font(.title2.bold())
            Text(summary).font(.headline)
            Text(details).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
    }
}

private func serviceBadge(_ kind: ServiceKind) -> String {
    switch kind {
    case .appleLocal: "内置"
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
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7)))
    }
    private var serviceIdentity: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 38, height: 38).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.blue)
            VStack(alignment: .leading) {
                TextField("服务名称", text: $service.name).font(.headline).textFieldStyle(.plain)
                Text(service.kind.rawValue).font(.caption).foregroundStyle(.secondary)
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
    private var needsPrimaryCredential: Bool { service.kind != .google && service.kind != .appleLocal }
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
    var body: some View {
        VStack(spacing: 0) {
            Header(title: "插件", subtitle: "使用 JavaScript 扩展翻译服务") {
                Button(action: model.installPlugin) { Label("安装插件", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            Divider()
            if model.plugins.isEmpty {
                EmptyHint(icon: "puzzlepiece.extension", title: "尚未安装插件", detail: "插件目录需要包含 manifest.json 和实现 translate(request) 的 main.js")
            } else {
                List {
                    ForEach($model.plugins) { $plugin in
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                pluginIdentity(plugin)
                                Spacer(minLength: 8)
                                pluginActions($plugin)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                pluginIdentity(plugin)
                                HStack { Spacer(minLength: 0); pluginActions($plugin) }
                            }
                        }.padding(.vertical, 8)
                    }
                }.onChange(of: model.plugins) { model.savePlugins() }
            }
        }
    }

    private func pluginIdentity(_ plugin: InstalledPlugin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill").font(.title2).foregroundStyle(.purple).frame(width: 42, height: 42).background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(plugin.name).font(.headline); Text("v\(plugin.version)").font(.caption).foregroundStyle(.secondary) }
                if let summary = plugin.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let author = plugin.author { Text(author).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }

    private func pluginActions(_ plugin: Binding<InstalledPlugin>) -> some View {
        HStack(spacing: 12) {
            Toggle("启用", isOn: plugin.enabled).labelsHidden()
            Button("卸载", role: .destructive) { model.uninstallPlugin(plugin.wrappedValue) }
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
                model.saveSettings()
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
        }.padding(.horizontal, 22).padding(.vertical, 15)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
