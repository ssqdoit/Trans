import SwiftUI
import XCTest
@testable import Trans

final class ScreenshotSelectionPolicyTests: XCTestCase {
    func testWaitsForOptionReleaseBeforeStartingSelection() {
        XCTAssertTrue(ScreenshotSelectionPolicy.shouldWaitForModifierRelease([.option]))
    }
}

final class SelectionGesturePolicyTests: XCTestCase {
    func testDoubleClickIsSelectionGesture() {
        XCTAssertTrue(SelectionGesturePolicy.isSelectionGesture(clickCount: 2, dragDistance: 0))
    }

    func testTripleClickIsSelectionGesture() {
        XCTAssertTrue(SelectionGesturePolicy.isSelectionGesture(clickCount: 3, dragDistance: 0))
    }

    func testDragBeyondThresholdIsSelectionGesture() {
        XCTAssertTrue(SelectionGesturePolicy.isSelectionGesture(clickCount: 1, dragDistance: 20))
    }

    func testDragAtThresholdIsSelectionGesture() {
        XCTAssertTrue(SelectionGesturePolicy.isSelectionGesture(
            clickCount: 1,
            dragDistance: SelectionGesturePolicy.dragThreshold
        ))
    }

    func testPlainClickWithTinyMovementIsNotSelectionGesture() {
        XCTAssertFalse(SelectionGesturePolicy.isSelectionGesture(clickCount: 1, dragDistance: 3))
    }
}

final class SelectionPresentationPolicyTests: XCTestCase {
    func testPresentsFreshText() {
        XCTAssertTrue(SelectionPresentationPolicy.shouldPresent(
            text: "hello", lastShownText: nil, dismissedText: nil, isPopupVisible: false
        ))
    }

    func testSkipsSameTextWhilePopupStillVisible() {
        XCTAssertFalse(SelectionPresentationPolicy.shouldPresent(
            text: "hello", lastShownText: "hello", dismissedText: nil, isPopupVisible: true
        ))
    }

    func testPresentsSameTextAgainAfterPopupDismissed() {
        XCTAssertTrue(SelectionPresentationPolicy.shouldPresent(
            text: "hello", lastShownText: "hello", dismissedText: nil, isPopupVisible: false
        ))
    }

    func testPresentsDifferentTextWhilePopupVisible() {
        XCTAssertTrue(SelectionPresentationPolicy.shouldPresent(
            text: "world", lastShownText: "hello", dismissedText: nil, isPopupVisible: true
        ))
    }

    func testSkipsNilAndWhitespaceOnlyText() {
        XCTAssertFalse(SelectionPresentationPolicy.shouldPresent(
            text: nil, lastShownText: nil, dismissedText: nil, isPopupVisible: false
        ))
        XCTAssertFalse(SelectionPresentationPolicy.shouldPresent(
            text: "  \n\t", lastShownText: nil, dismissedText: nil, isPopupVisible: false
        ))
    }

    func testSkipsExplicitlyClosedTextWhileStillSelected() {
        // 用户点关闭后，源应用里的旧选区在后续拖拽手势中仍会被读到，
        // 不应让小窗自动重现。
        XCTAssertFalse(SelectionPresentationPolicy.shouldPresent(
            text: "hello", lastShownText: "hello", dismissedText: "hello", isPopupVisible: false
        ))
    }

    func testPresentsNewSelectionAfterExplicitClose() {
        XCTAssertTrue(SelectionPresentationPolicy.shouldPresent(
            text: "world", lastShownText: "hello", dismissedText: "hello", isPopupVisible: false
        ))
    }
}

final class PopupPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 320, height: 200)

    func testPlacesBelowRightOfCursorByDefault() {
        let origin = PopupPlacement.origin(mouse: CGPoint(x: 100, y: 500), panelSize: size, screen: screen)
        XCTAssertEqual(origin.x, 112) // mouse.x + 12pt offset
        XCTAssertEqual(origin.y, 288) // mouse.y - offset - panel height
    }

    func testClampsToRightScreenEdge() {
        let origin = PopupPlacement.origin(mouse: CGPoint(x: 1400, y: 500), panelSize: size, screen: screen)
        XCTAssertEqual(origin.x, 1440 - 8 - 320) // screen.maxX - margin - width
    }

    func testFlipsAboveCursorWhenNoRoomBelow() {
        let origin = PopupPlacement.origin(mouse: CGPoint(x: 100, y: 150), panelSize: size, screen: screen)
        XCTAssertEqual(origin.y, 162) // mouse.y + offset
    }

    func testNeverPlacesOutsideScreenVertically() {
        let origin = PopupPlacement.origin(mouse: CGPoint(x: 100, y: 895), panelSize: size, screen: screen)
        XCTAssertLessThanOrEqual(origin.y + size.height, screen.maxY - 8)
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY + 8)
    }

    func testAnchoredResizeKeepsTopLeftCorner() {
        let current = CGRect(x: 400, y: 300, width: 320, height: 200)
        let origin = PopupPlacement.anchoredOrigin(
            currentFrame: current,
            newSize: CGSize(width: 320, height: 260),
            screen: screen
        )
        XCTAssertEqual(origin.x, 400)
        XCTAssertEqual(origin.y, current.maxY - 260) // 顶边不动，向下生长
    }

    func testAnchoredResizeClampsInsideScreen() {
        let current = CGRect(x: 1300, y: 10, width: 320, height: 200)
        let origin = PopupPlacement.anchoredOrigin(
            currentFrame: current,
            newSize: CGSize(width: 320, height: 400),
            screen: screen
        )
        XCTAssertLessThanOrEqual(origin.x + 320, screen.maxX - 8)
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY + 8)
    }
}

final class MenuShortcutParserTests: XCTestCase {
    func testParsesOptionLetterShortcut() {
        let shortcut = MenuShortcutParser.shortcut(from: "⌥S")
        XCTAssertEqual(shortcut, KeyboardShortcut("s", modifiers: .option))
    }

    func testParsesMultipleModifiers() {
        let shortcut = MenuShortcutParser.shortcut(from: "⌃⇧⌘D")
        XCTAssertEqual(shortcut, KeyboardShortcut("d", modifiers: [.control, .shift, .command]))
    }

    func testReturnsNilForModifierOnlyOrEmptyString() {
        XCTAssertNil(MenuShortcutParser.shortcut(from: ""))
        XCTAssertNil(MenuShortcutParser.shortcut(from: "⌥"))
    }
}

final class HotKeyRegistrationReportTests: XCTestCase {
    func testNoFailuresProducesNoWarning() {
        XCTAssertNil(HotKeyRegistrationReport.warningMessage(failedShortcuts: []))
    }

    func testFailedShortcutsAreListedInWarning() {
        let message = HotKeyRegistrationReport.warningMessage(failedShortcuts: ["⌥S", "⌥T"])
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("⌥S") == true)
        XCTAssertTrue(message?.contains("⌥T") == true)
        XCTAssertTrue(message?.contains("占用") == true)
    }
}

final class OCRPresentationPolicyTests: XCTestCase {
    func testScreenshotTranslationAlwaysUsesPopup() {
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .screenshotTranslation, isAppActive: true))
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .screenshotTranslation, isAppActive: false))
    }

    func testScreenshotRecognitionUsesPopupOnlyWhenAppInBackground() {
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .screenshotRecognition, isAppActive: false))
        XCTAssertFalse(OCRPresentationPolicy.shouldShowPopup(trigger: .screenshotRecognition, isAppActive: true))
    }

    func testSilentScreenshotAlwaysShowsPopup() {
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .silentScreenshot, isAppActive: true))
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .silentScreenshot, isAppActive: false))
    }

    func testClipboardShowsPopupOnlyWhenAppInBackground() {
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .clipboard, isAppActive: false))
        XCTAssertFalse(OCRPresentationPolicy.shouldShowPopup(trigger: .clipboard, isAppActive: true))
    }

    func testContinuousShowsPopupOnlyWhenAppInBackground() {
        XCTAssertTrue(OCRPresentationPolicy.shouldShowPopup(trigger: .continuous, isAppActive: false))
        XCTAssertFalse(OCRPresentationPolicy.shouldShowPopup(trigger: .continuous, isAppActive: true))
    }

    func testFailedRecognitionNeverPresentsStaleText() {
        XCTAssertEqual(
            OCRPopupResultPolicy.presentation(for: .failure(message: "Vision error")),
            .message("识别失败：Vision error")
        )
    }

    func testSuccessfulRecognitionRequiresNonemptyText() {
        XCTAssertEqual(
            OCRPopupResultPolicy.presentation(for: .success(text: "fresh text")),
            .translate(text: "fresh text")
        )
        XCTAssertEqual(
            OCRPopupResultPolicy.presentation(for: .success(text: "  \n")),
            .message("未识别到文字")
        )
    }

    func testSupersededRecognitionDoesNotTouchPopup() {
        XCTAssertEqual(OCRPopupResultPolicy.presentation(for: .superseded), .none)
    }
}

final class LanguageSwapPolicyTests: XCTestCase {
    func testSwapsConcreteLanguagePair() {
        let swapped = LanguageSwapPolicy.swapped(source: .english, target: .zhHans)
        XCTAssertEqual(swapped.source, .zhHans)
        XCTAssertEqual(swapped.target, .english)
    }

    func testAutoSourceBecomesTargetAndChineseTargetFallsBackToEnglish() {
        let swapped = LanguageSwapPolicy.swapped(source: .auto, target: .zhHans)
        XCTAssertEqual(swapped.source, .zhHans)
        XCTAssertEqual(swapped.target, .english)
    }

    func testAutoSourceWithNonChineseTargetFallsBackToChinese() {
        let swapped = LanguageSwapPolicy.swapped(source: .auto, target: .japanese)
        XCTAssertEqual(swapped.source, .japanese)
        XCTAssertEqual(swapped.target, .zhHans)
    }
}

final class AppSettingsDecodingTests: XCTestCase {
    func testOldSettingsFileWithoutNewKeysStillDecodes() throws {
        let oldJSON = """
        {"launchAtLogin":true,"keepOnTop":false,"autoTranslate":false,"copyAfterOCR":true,
         "smartParagraphs":true,"rememberWindow":true,"selectionHotKey":"⌥S",
         "screenshotHotKey":"⌥D","inputHotKey":"⌥A","ocrHotKey":"⌥F",
         "inputBoxHotKey":"⌥T","interfaceLanguage":"简体中文"}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(settings.launchAtLogin, true)
        XCTAssertEqual(settings.keepOnTop, false)
        XCTAssertTrue(settings.selectionPopupEnabled, "缺失新键时应默认开启划词弹窗")
    }

    func testPartialSettingsFileDecodesWithDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, AppSettings())
    }
}
