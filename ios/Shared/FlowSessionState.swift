import Foundation

enum FlowSessionState {
    static let appGroup = "group.dev.smathdaddy.openwispr"

    enum Keys {
        static let sessionActive = "fs.sessionActive"
        static let sessionExpiresAt = "fs.sessionExpiresAt"
        static let utteranceCounter = "fs.utteranceCounter"
        static let utteranceInProgress = "fs.utteranceInProgress"
        static let latestTranscript = "fs.latestTranscript"
        static let latestTranscriptCounter = "fs.latestTranscriptCounter"
        static let lastInsertedCounter = "fs.lastInsertedCounter"
        static let errorMessage = "fs.errorMessage"
    }

    enum DarwinNotification {
        static let startUtterance = "dev.smathdaddy.openwispr.startUtterance"
        static let stopUtterance = "dev.smathdaddy.openwispr.stopUtterance"
        static let transcriptReady = "dev.smathdaddy.openwispr.transcriptReady"
        static let sessionEnded = "dev.smathdaddy.openwispr.sessionEnded"
        static let utteranceAck = "dev.smathdaddy.openwispr.utteranceAck"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var sessionActive: Bool {
        get { defaults.bool(forKey: Keys.sessionActive) }
        set { defaults.set(newValue, forKey: Keys.sessionActive) }
    }

    static var sessionExpiresAt: Date? {
        get { defaults.object(forKey: Keys.sessionExpiresAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.sessionExpiresAt) }
    }

    static var utteranceCounter: Int {
        get { defaults.integer(forKey: Keys.utteranceCounter) }
        set { defaults.set(newValue, forKey: Keys.utteranceCounter) }
    }

    static var utteranceInProgress: Bool {
        get { defaults.bool(forKey: Keys.utteranceInProgress) }
        set { defaults.set(newValue, forKey: Keys.utteranceInProgress) }
    }

    static var latestTranscript: String? {
        get { defaults.string(forKey: Keys.latestTranscript) }
        set { defaults.set(newValue, forKey: Keys.latestTranscript) }
    }

    static var latestTranscriptCounter: Int {
        get { defaults.integer(forKey: Keys.latestTranscriptCounter) }
        set { defaults.set(newValue, forKey: Keys.latestTranscriptCounter) }
    }

    static var lastInsertedCounter: Int {
        get { defaults.integer(forKey: Keys.lastInsertedCounter) }
        set { defaults.set(newValue, forKey: Keys.lastInsertedCounter) }
    }

    static var errorMessage: String? {
        get { defaults.string(forKey: Keys.errorMessage) }
        set { defaults.set(newValue, forKey: Keys.errorMessage) }
    }

    static var isSessionActiveAndUnexpired: Bool {
        guard sessionActive else { return false }
        if let expires = sessionExpiresAt, expires < Date() { return false }
        return true
    }
}

enum DarwinNotify {
    static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }

    static func observe(_ name: String, observer: UnsafeMutableRawPointer, callback: CFNotificationCallback) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = name as CFString
        CFNotificationCenterAddObserver(center, observer, callback, cfName, nil, .deliverImmediately)
    }

    static func remove(_ name: String, observer: UnsafeMutableRawPointer) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterRemoveObserver(center, observer, cfName, nil)
    }
}
