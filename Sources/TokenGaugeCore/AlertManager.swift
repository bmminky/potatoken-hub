import Foundation
import UserNotifications

/// Fires a local notification the moment a window hits 0% remaining, and again
/// when it resets back up. Each event is keyed by window id so it fires at most
/// once per exhaustion/reset cycle, not once per 15-second poll.
public final class AlertManager: @unchecked Sendable {
    public static let shared = AlertManager()

    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var lastRemaining: [String: Double] = [:]
    private var exhaustionAlerted: Set<String> = []

    private init() {}

    public func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func process(window: UsageWindow) {
        guard let remaining = window.remainingPercent else { return }
        lock.lock()
        let previous = lastRemaining[window.id]
        lastRemaining[window.id] = remaining
        let alreadyAlerted = exhaustionAlerted.contains(window.id)
        lock.unlock()

        if remaining <= 0.01 {
            guard !alreadyAlerted else { return }
            lock.lock(); exhaustionAlerted.insert(window.id); lock.unlock()
            notify(
                title: L.t(
                    ko: "\(window.provider.rawValue) \(window.label) 소진",
                    en: "\(window.provider.rawValue) \(window.label) exhausted",
                    ja: "\(window.provider.rawValue) \(window.label) 使い切り",
                    zh: "\(window.provider.rawValue) \(window.label) 已用完"
                ),
                body: L.t(
                    ko: "사용 가능한 한도가 0%입니다.",
                    en: "You're out of quota for this window.",
                    ja: "この期間の利用可能な割り当てが0%になりました。",
                    zh: "该时间段的可用配额已为0%。"
                )
            )
        } else {
            if let previous, previous <= 0.01 {
                notify(
                    title: L.t(
                        ko: "\(window.provider.rawValue) \(window.label) 리셋",
                        en: "\(window.provider.rawValue) \(window.label) reset",
                        ja: "\(window.provider.rawValue) \(window.label) リセット",
                        zh: "\(window.provider.rawValue) \(window.label) 已重置"
                    ),
                    body: L.t(
                        ko: "한도가 초기화되었습니다. 남은 한도 \(Int(remaining))%.",
                        en: "Your quota has reset. \(Int(remaining))% remaining.",
                        ja: "割り当てがリセットされました。残り\(Int(remaining))%。",
                        zh: "配额已重置。剩余\(Int(remaining))%。"
                    )
                )
            }
            lock.lock(); exhaustionAlerted.remove(window.id); lock.unlock()
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
