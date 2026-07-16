import Foundation

/// Cross-process signaling between the app and its extensions via Darwin
/// notifications. Payloads still travel through the App Group; these
/// notifications just replace tight polling loops with instant wake-ups.
enum KordIPCEvent: String, CaseIterable {
    /// Keyboard -> app: a dictation command was written.
    case command = "dev.smathdaddy.openwispr.ipc.command"
    /// App -> keyboard: a dictation result was written.
    case result = "dev.smathdaddy.openwispr.ipc.result"
    /// App -> keyboard: engine status/heartbeat changed.
    case state = "dev.smathdaddy.openwispr.ipc.state"

    var cfName: CFNotificationName {
        CFNotificationName(rawValue as CFString)
    }
}

enum KordIPC {
    static func post(_ event: KordIPCEvent) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            event.cfName,
            nil,
            nil,
            true
        )
    }
}

/// Registers Darwin observers and forwards them to a callback on the main queue.
/// Keep the instance alive for as long as you want to observe.
final class KordIPCObserver {
    private var handlers: [KordIPCEvent: () -> Void] = [:]

    init() {}

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func observe(_ event: KordIPCEvent, handler: @escaping () -> Void) {
        handlers[event] = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let instance = Unmanaged<KordIPCObserver>.fromOpaque(observer).takeUnretainedValue()
                guard let event = KordIPCEvent(rawValue: name.rawValue as String) else { return }
                DispatchQueue.main.async {
                    instance.handlers[event]?()
                }
            },
            event.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }
}
