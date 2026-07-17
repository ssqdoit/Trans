import Foundation
import CoreGraphics

enum SelectionGesturePolicy {
    static let dragThreshold: CGFloat = 8

    static func isSelectionGesture(clickCount: Int, dragDistance: CGFloat) -> Bool {
        clickCount >= 2 || dragDistance >= dragThreshold
    }
}

enum SelectionPresentationPolicy {
    static func shouldPresent(text: String?, lastShownText: String?, isPopupVisible: Bool) -> Bool {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !(isPopupVisible && text == lastShownText)
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
}

enum HotKeyRegistrationReport {
    static func warningMessage(failedShortcuts: [String]) -> String? {
        guard !failedShortcuts.isEmpty else { return nil }
        return "快捷键 \(failedShortcuts.joined(separator: "、")) 注册失败，可能已被其他应用占用，请检查冲突后重启 Trans。"
    }
}

enum OCRPopupTrigger {
    case screenshotTranslation
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
