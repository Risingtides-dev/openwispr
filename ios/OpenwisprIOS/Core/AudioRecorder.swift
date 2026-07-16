import AVFoundation
import os

private let recorderLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "AudioRecorder")

final class AudioRecorder: NSObject, ObservableObject {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startedAt: Date?

    func start() throws {
        recorderLog.info("start requested")
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true, options: [])
        recorderLog.info("audio session active")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwispr-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        guard rec.record() else {
            recorderLog.error("AVAudioRecorder.record returned false")
            throw NSError(
                domain: "openwispr.recorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() returned false"]
            )
        }
        recorder = rec
        fileURL = url
        startedAt = Date()
        recorderLog.info("recording started")
    }

    func stop() throws -> URL {
        recorderLog.info("stop requested")
        guard let recorder, let fileURL else {
            recorderLog.error("stop requested while not recording")
            throw NSError(
                domain: "openwispr.recorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Not recording"]
            )
        }
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.intValue ?? -1
        recorderLog.info("recording stopped duration=\(duration, privacy: .public) size=\(size, privacy: .public)")
        return fileURL
    }
}
