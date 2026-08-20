import Foundation
import CoreGraphics
import SwiftUI

enum SelectionGesturePolicy {
    static let dragThreshold: CGFloat = 8

    static func isSelectionGesture(clickCount: Int, dragDistance: CGFloat) -> Bool {
        clickCount >= 2 || dragDistance >= dragThreshold
    }
}

enum SelectionPresentationPolicy {
    static func shouldPresent(
        text: String?,
        lastShownText: String?,
        dismissedText: String?,
        isPopupVisible: Bool
    ) -> Bool {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if isPopupVisible, text == lastShownText { return false }
        // A selection lingering in the source app keeps producing the same
        // text on later drag gestures; don't resurrect an explicitly closed
        // popup until the user selects something else.
        if !isPopupVisible, text == dismissedText { return false }
        return true
    }
}

enum PopupPlacement {
    static func origin(
        mouse: CGPoint,
        panelSize: CGSize,
        screen: CGRect,
        offset: CGFloat = 12,
        margin: CGFloat = 8
    ) -> CGPoint {
        var x = mouse.x + offset
        x = min(x, screen.maxX - margin - panelSize.width)
        x = max(x, screen.minX + margin)
        var y = mouse.y - offset - panelSize.height
        if y < screen.minY + margin {
            y = mouse.y + offset
        }
        y = min(y, screen.maxY - margin - panelSize.height)
        y = max(y, screen.minY + margin)
        return CGPoint(x: x, y: y)
    }

    /// Resizes an already-visible (possibly user-moved) panel in place: the
    /// top-left corner stays fixed and the panel grows downward.
    static func anchoredOrigin(
        currentFrame: CGRect,
        newSize: CGSize,
        screen: CGRect,
        margin: CGFloat = 8
    ) -> CGPoint {
        var x = currentFrame.minX
        var y = currentFrame.maxY - newSize.height
        x = min(x, screen.maxX - margin - newSize.width)
        x = max(x, screen.minX + margin)
        y = min(y, screen.maxY - margin - newSize.height)
        y = max(y, screen.minY + margin)
        return CGPoint(x: x, y: y)
    }
}

/// Parses a settings shortcut label like "⌥S" into a SwiftUI shortcut so
/// menu-bar items can display it natively. The Carbon hot key swallows the
/// key event system-wide, so the menu equivalent is display-only.
enum MenuShortcutParser {
    static func shortcut(from label: String) -> KeyboardShortcut? {
        var modifiers: EventModifiers = []
        var key: Character?
        for character in label {
            switch character {
            case "⌘": modifiers.insert(.command)
            case "⌥": modifiers.insert(.option)
            case "⇧": modifiers.insert(.shift)
            case "⌃": modifiers.insert(.control)
            default: key = character
            }
        }
        guard let key, let lowered = key.lowercased().first else { return nil }
        return KeyboardShortcut(KeyEquivalent(lowered), modifiers: modifiers)
    }
}

enum HotKeyRegistrationReport {
    static func warningMessage(failedShortcuts: [String]) -> String? {
        guard !failedShortcuts.isEmpty else { return nil }
        return "快捷键 \(failedShortcuts.joined(separator: "、")) 注册失败，可能已被其他应用占用，请检查冲突后重启 Trans。"
    }
}

enum OCRPopupTrigger {
    case screenshotTranslation
    case screenshotRecognition
    case silentScreenshot
    case clipboard
    case continuous
}

/// Decides whether an OCR entry point should surface results in the floating
/// popup instead of (only) the main window.
enum OCRPresentationPolicy {
    static func shouldShowPopup(trigger: OCRPopupTrigger, isAppActive: Bool) -> Bool {
        switch trigger {
        case .screenshotTranslation: return true
        case .screenshotRecognition: return !isAppActive
        case .silentScreenshot: return true
        case .clipboard, .continuous: return !isAppActive
        }
    }
}

enum OCRRecognitionOutcome: Equatable {
    case success(text: String)
    case failure(message: String)
    case superseded
}

enum OCRPopupPresentation: Equatable {
    case translate(text: String)
    case message(String)
    case none
}

enum OCRPopupResultPolicy {
    static func presentation(for outcome: OCRRecognitionOutcome) -> OCRPopupPresentation {
        switch outcome {
        case .success(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .translate(text: text)
        case .success:
            return .message("未识别到文字")
        case .failure(let message):
            return .message("识别失败：\(message)")
        case .superseded:
            return .none
        }
    }
}

enum LanguageSwapPolicy {
    static func swapped(source: Language, target: Language) -> (source: Language, target: Language) {
        guard source != .auto else {
            return (target, target == .zhHans ? .english : .zhHans)
        }
        return (target, source)
    }
}
