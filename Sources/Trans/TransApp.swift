import SwiftUI

@main
struct TransApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Trans") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 450, minHeight: 310)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("输入翻译") { model.selectedSection = .translate }
                    .keyboardShortcut("a", modifiers: [.option])
                Button("截图 OCR") { Task { await model.screenshotAndRecognize() } }
                    .keyboardShortcut("d", modifiers: [.option])
                Button("静默截图 OCR") { Task { await model.screenshotAndRecognize(silent: true) } }
                    .keyboardShortcut("f", modifiers: [.option])
                Button("重新翻译") { Task { await model.translate(mode: "重试") } }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        // MenuBarExtra bridges to NSMenu, which drops custom label layouts;
        // shortcuts must go through keyboardShortcut to be displayed. The
        // Carbon hot keys consume these key events system-wide, so the menu
        // equivalents shown here never double-fire.
        MenuBarExtra {
            Button("输入翻译") {
                model.selectedSection = .translate
                NSApp.activate(ignoringOtherApps: true)
            }
            .menuShortcut(model.settings.inputHotKey)
            Button("划词翻译") { Task { await model.translateSelectionPopup() } }
                .menuShortcut(model.settings.selectionHotKey)
            Button("静默划词翻译") { Task { await model.translateSelection(silent: true) } }
            Button("输入框翻译") { Task { await model.translateInputBox() } }
                .menuShortcut(model.settings.inputBoxHotKey)
            Divider()
            Button("截图翻译") { Task { await model.screenshotAndTranslate() } }
            Button("截图 OCR") { Task { await model.screenshotAndRecognize() } }
                .menuShortcut(model.settings.screenshotHotKey)
            Button("静默截图 OCR") { Task { await model.screenshotAndRecognize(silent: true) } }
                .menuShortcut(model.settings.ocrHotKey)
            Divider()
            Button("退出 Trans") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: TransMenuBarIcon.image)
                .accessibilityLabel("Trans")
        }
    }
}

private extension View {
    @ViewBuilder func menuShortcut(_ label: String) -> some View {
        if let shortcut = MenuShortcutParser.shortcut(from: label) {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}

private enum TransMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let rim = NSBezierPath(
                roundedRect: NSRect(x: 2.5, y: 13, width: 13, height: 2.4),
                xRadius: 1.2,
                yRadius: 1.2
            )
            rim.fill()

            let glass = NSBezierPath()
            glass.move(to: NSPoint(x: 4, y: 13.6))
            glass.line(to: NSPoint(x: 5, y: 4.3))
            glass.curve(
                to: NSPoint(x: 7, y: 2.6),
                controlPoint1: NSPoint(x: 5.2, y: 3.1),
                controlPoint2: NSPoint(x: 5.8, y: 2.6)
            )
            glass.line(to: NSPoint(x: 11, y: 2.6))
            glass.curve(
                to: NSPoint(x: 13, y: 4.3),
                controlPoint1: NSPoint(x: 12.2, y: 2.6),
                controlPoint2: NSPoint(x: 12.8, y: 3.1)
            )
            glass.line(to: NSPoint(x: 14, y: 13.6))
            glass.lineWidth = 1.7
            glass.lineCapStyle = .round
            glass.lineJoinStyle = .round
            glass.stroke()

            let water = NSBezierPath()
            water.move(to: NSPoint(x: 5.3, y: 7.2))
            water.curve(
                to: NSPoint(x: 9, y: 6.9),
                controlPoint1: NSPoint(x: 6.5, y: 7.5),
                controlPoint2: NSPoint(x: 7.7, y: 6.5)
            )
            water.curve(
                to: NSPoint(x: 12.7, y: 7.1),
                controlPoint1: NSPoint(x: 10.3, y: 7.3),
                controlPoint2: NSPoint(x: 11.5, y: 6.8)
            )
            water.line(to: NSPoint(x: 12.4, y: 4.5))
            water.curve(
                to: NSPoint(x: 10.8, y: 3.4),
                controlPoint1: NSPoint(x: 12.2, y: 3.8),
                controlPoint2: NSPoint(x: 11.7, y: 3.4)
            )
            water.line(to: NSPoint(x: 7.2, y: 3.4))
            water.curve(
                to: NSPoint(x: 5.6, y: 4.5),
                controlPoint1: NSPoint(x: 6.3, y: 3.4),
                controlPoint2: NSPoint(x: 5.8, y: 3.8)
            )
            water.close()
            water.fill()

            return true
        }
        image.isTemplate = true
        return image
    }()
}
