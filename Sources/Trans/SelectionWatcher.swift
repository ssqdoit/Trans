import AppKit
import ApplicationServices

enum AXSelectionReader {
    static func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else { return nil }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success else { return nil }
        return selectedValue as? String
    }
}

/// Watches mouse gestures in other applications and reads the resulting text
/// selection through Accessibility. Global monitors never receive this app's
/// own events, so selections inside Trans never trigger the popup.
@MainActor
final class SelectionWatcher {
    var onSelection: ((String, CGPoint) -> Void)?
    private var monitors: [Any] = []
    private var mouseDownLocation = CGPoint.zero
    private var readTask: Task<Void, Never>?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            let location = Self.screenLocation(of: event)
            Task { @MainActor in self?.mouseDownLocation = location }
        })
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            let location = Self.screenLocation(of: event)
            let clickCount = event.clickCount
            Task { @MainActor in self?.handleMouseUp(clickCount: clickCount, location: location) }
        })
        monitors = [down, up].compactMap { $0 }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        readTask?.cancel()
        readTask = nil
        isRunning = false
    }

    private func handleMouseUp(clickCount: Int, location: CGPoint) {
        let distance = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        guard SelectionGesturePolicy.isSelectionGesture(clickCount: clickCount, dragDistance: distance) else { return }
        guard AXIsProcessTrusted() else { return }
        readTask?.cancel()
        readTask = Task { [weak self] in
            // Give the frontmost app a beat to commit its selection state.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            guard let text = AXSelectionReader.selectedText() else { return }
            guard !Task.isCancelled else { return }
            self.onSelection?(text, location)
        }
    }

    private nonisolated static func screenLocation(of event: NSEvent) -> CGPoint {
        // Global monitor events come from other apps and carry no window,
        // so locationInWindow is already in screen coordinates.
        event.locationInWindow
    }

    deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
