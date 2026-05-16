import AVFoundation

final class AudioRecorder: NSObject, ObservableObject {
    @Published var level: Double = 0
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTimer: Timer?

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
        rec.isMeteringEnabled = true
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
        startMetering()
    }

    func stop() throws -> URL {
        guard let recorder, let fileURL else {
            throw NSError(
                domain: "openwispr.recorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Not recording"]
            )
        }
        stopMetering()
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return fileURL
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder else { return }
            rec.updateMeters()
            let db = Double(rec.averagePower(forChannel: 0))
            let normalized = max(0, min(1, (db + 50) / 50))
            DispatchQueue.main.async { self.level = normalized }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        DispatchQueue.main.async { self.level = 0 }
    }
}
