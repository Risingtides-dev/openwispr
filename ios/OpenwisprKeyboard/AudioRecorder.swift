import AVFoundation

final class AudioRecorder: NSObject, ObservableObject {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() throws {
        let perm = AVAudioApplication.shared.recordPermission
        guard perm == .granted else {
            let label = perm == .denied ? "denied" : "not asked"
            throw NSError(
                domain: "openwispr.recorder",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Mic permission \(label). Open the openwispr app first."]
            )
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwispr-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        guard rec.prepareToRecord() else {
            throw NSError(
                domain: "openwispr.recorder",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "prepareToRecord returned false (file: \(url.lastPathComponent))"]
            )
        }
        guard rec.record() else {
            let route = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
            throw NSError(
                domain: "openwispr.recorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "record returned false (inputs: \(route.isEmpty ? "none" : route))"]
            )
        }
        recorder = rec
        fileURL = url
    }

    func stop() throws -> URL {
        guard let recorder, let fileURL else {
            throw NSError(
                domain: "openwispr.recorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Not recording"]
            )
        }
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return fileURL
    }
}
