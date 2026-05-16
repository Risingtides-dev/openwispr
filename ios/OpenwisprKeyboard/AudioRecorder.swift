import AVFoundation

final class AudioRecorder: NSObject, ObservableObject {
    @Published var level: Double = 0
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
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
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwispr-\(UUID().uuidString).wav")

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        let newFile = try AVAudioFile(forWriting: url, settings: inputFormat.settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            if let chData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                if frames > 0 {
                    var sum: Float = 0
                    for i in 0..<frames {
                        let s = chData[i]
                        sum += s * s
                    }
                    let rms = sqrt(sum / Float(frames))
                    let db = 20 * log10(max(rms, 0.0000001))
                    let normalized = max(0, min(1, Double((db + 50) / 50)))
                    DispatchQueue.main.async { self.level = normalized }
                }
            }
        }

        newEngine.prepare()
        try newEngine.start()

        self.engine = newEngine
        self.file = newFile
        self.fileURL = url
    }

    func stop() throws -> URL {
        guard let engine, let fileURL else {
            throw NSError(
                domain: "openwispr.recorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Not recording"]
            )
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.file = nil
        self.fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.level = 0 }
        return fileURL
    }
}
