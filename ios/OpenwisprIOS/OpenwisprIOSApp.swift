import SwiftUI

@main
struct OpenwisprIOSApp: App {
    @StateObject private var session = FlowSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onOpenURL { url in
                    handle(url: url)
                }
        }
    }

    private func handle(url: URL) {
        guard url.scheme == "openwispr" else { return }
        switch url.host {
        case "startSession":
            session.startSession()
        case "stopSession":
            session.stopSession()
        default:
            break
        }
    }
}
