import SwiftUI
import Translation

/// 通过挂在主窗口上的 `translationTask` 承接 Apple 本地翻译请求。
/// 直接创建的 `TranslationSession` 无法发起语言包下载（`canRequestDownloads == false`），
/// 只有视图承载的会话才能弹出系统下载确认，从而做到零配置。
@available(macOS 15.0, *)
@MainActor
final class AppleTranslationBridge: ObservableObject {
    static let shared = AppleTranslationBridge()

    @Published private(set) var configuration: TranslationSession.Configuration?

    private struct Request {
        let text: String
        let source: Locale.Language
        let target: Locale.Language
        let continuation: CheckedContinuation<String, Error>
    }

    private var pending: [Request] = []
    private var active: Request?
    private var isProcessing = false
    private var hostCount = 0

    func hostDidAppear() {
        hostCount += 1
    }

    func hostDidDisappear() {
        hostCount = max(0, hostCount - 1)
        guard hostCount == 0 else { return }
        let cancelled = pending
        pending.removeAll()
        if let request = active, !isProcessing {
            active = nil
            request.continuation.resume(throwing: TransError.service("Trans 主窗口已关闭，Apple 本地翻译已取消"))
        }
        for request in cancelled {
            request.continuation.resume(throwing: TransError.service("Trans 主窗口已关闭，Apple 本地翻译已取消"))
        }
    }

    func translate(text: String, source: Locale.Language, target: Locale.Language) async throws -> String {
        guard hostCount > 0 else {
            throw TransError.service("请打开 Trans 主窗口后重试，以便系统完成语言包确认")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(Request(text: text, source: source, target: target, continuation: continuation))
            startNextIfIdle()
        }
    }

    fileprivate func run(with session: TranslationSession) async {
        guard let request = active, !isProcessing else { return }
        isProcessing = true
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(request.text)
            request.continuation.resume(returning: response.targetText)
        } catch {
            request.continuation.resume(throwing: error)
        }
        active = nil
        isProcessing = false
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard active == nil, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        active = request
        if var current = configuration, current.source == request.source, current.target == request.target {
            current.invalidate()
            configuration = current
        } else {
            configuration = TranslationSession.Configuration(source: request.source, target: request.target)
        }
    }
}

@available(macOS 15.0, *)
struct AppleTranslationHost: View {
    @ObservedObject private var bridge = AppleTranslationBridge.shared

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .translationTask(bridge.configuration) { session in
                await bridge.run(with: session)
            }
            .onAppear { bridge.hostDidAppear() }
            .onDisappear { bridge.hostDidDisappear() }
    }
}
