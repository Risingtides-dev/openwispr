import Foundation

enum AppBrand {
    static let name = "Windtalker"
    static let tagline = "Vocal keyboard"
    static let primaryScheme = "windtalker"
    static let legacyScheme = "openwispr"

    static func url(_ host: String) -> URL? {
        URL(string: "\(primaryScheme)://\(host)")
    }
}
