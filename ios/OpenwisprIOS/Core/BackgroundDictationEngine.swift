import AVFoundation
import Foundation
import os

private let engineLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "BackgroundEngine")

private final class ActiveDictationSession {
    let id: String
    let assembler = RollingTranscriptAssembler()
    let startedAt = Date()

    private let lock = NSLock()
    private var transcriptionTail: Task<Void, Never>?
    private var chunkErrors: [String] = []

    init(id: String) {
        self.id = id
    }

    func enqueueChunk(index: Int, fileURL: URL) {
        lock.lock()
        let previous = transcriptionTail
        let task = Task {
            await previous?.value
            defer { try? FileManager.default.removeItem(at: fileURL) }

            do {
                let start = Date()
                let raw = try await TranscriptionPipeline.transcribeRaw(fileURL: fileURL)
                assembler.setChunk(index: index, text: raw)
                let elapsedMs = Date().timeIntervalSince(start) * 1000
                engineLog.info("chunk transcribed id=\(self.id, privacy: .public) index=\(index, privacy: .public) rawLength=\(raw.count, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)")
            } catch {
                addChunkError("chunk \(index): \(error.localizedDescription)")
                engineLog.error("chunk transcription failed id=\(self.id, privacy: .public) index=\(index, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        transcriptionTail = task
        lock.unlock()
    }

    func waitForChunks() async {
        let tail = snapshotTail()
        await tail?.value
        clearTail()
    }

    func errors() -> [String] {
        lock.lock()
        let copy = chunkErrors
        lock.unlock()
        return copy
    }

    private func addChunkError(_ error: String) {
        lock.lock()
        chunkErrors.append(error)
        lock.unlock()
    }

    private func snapshotTail() -> Task<Void, Never>? {
        lock.lock()
        let tail = transcriptionTail
        lock.unlock()
        return tail
    }

    private func clearTail() {
        lock.lock()
        transcriptionTail = nil
        lock.unlock()
    }
}

final class BackgroundDictationEngine: ObservableObject {
    static let shared = BackgroundDictationEngine()

    @Published private(set) var status: EngineStatus = .inactive
    @Published private(set) var lastError: String?
    @Published private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private let audioLock = NSLock()
    private let ipcObserver = KordIPCObserver()
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    /// 16 kHz mono float32 — converted before hitting disk so chunk uploads are
    /// ~6x smaller than raw hardware-rate captures.
    private let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    private let chunkFileSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    private var audioFile: AVAudioFile?
    private var archiveAudioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var archiveFileURL: URL?
    private var currentRequestID: String?
    private var currentSession: ActiveDictationSession?
    private var currentChunkIndex = 0
    private var lastHandledCommand: DictationCommand?
    private var heartbeatTimer: Timer?
    private var commandTimer: Timer?
    private var chunkTimer: Timer?
    private var tapInstalled = false
    private var lastLevelPublishAt: TimeInterval = 0
    private var overlapBuffers: [AVAudioPCMBuffer] = []
    private var overlapFrameCount: AVAudioFramePosition = 0
    private let overlapDuration: TimeInterval = 0.55

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        // Commands arrive instantly via Darwin notification; the timer below
        // is only a fallback in case a notification is dropped.
        ipcObserver.observe(.command) { [weak self] in
            self?.pollCommand()
        }
    }

    func activate() {
        engineLog.info("activate requested")
        SharedConfig.resetResidentDictationState()
        Task {
            let allowed = await requestMicPermission()
            guard allowed else {
                await setError("Microphone permission is required.")
                return
            }

            do {
                try startAudioSessionIfNeeded()
                await MainActor.run {
                    startTimers()
                    setStatus(.armed)
                }
                engineLog.info("engine armed")
            } catch {
                await setError(error.localizedDescription)
            }
        }
    }

    private func requestMicPermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func startAudioSessionIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setPreferredSampleRate(16_000)
        try? session.setPreferredInputNumberOfChannels(1)
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        if inputFormat != format || converter == nil {
            converter = AVAudioConverter(from: format, to: targetFormat)
        }
        inputFormat = format
        engineLog.info("audio session active sampleRate=\(session.sampleRate, privacy: .public) channels=\(session.inputNumberOfChannels, privacy: .public) buffer=\(session.ioBufferDuration, privacy: .public) formatRate=\(format.sampleRate, privacy: .public) formatChannels=\(format.channelCount, privacy: .public)")

        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.writeBufferIfRecording(buffer)
            }
            tapInstalled = true
        }

        if !engine.isRunning {
            try engine.start()
        }
    }

    private func writeBufferIfRecording(_ buffer: AVAudioPCMBuffer) {
        publishLevel(from: buffer)

        audioLock.lock()
        defer { audioLock.unlock() }
        guard audioFile != nil || archiveAudioFile != nil else { return }
        guard let converted = downsample(buffer) else { return }

        if let file = audioFile {
            do {
                try file.write(from: converted)
            } catch {
                engineLog.error("chunk buffer write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let archive = archiveAudioFile {
            do {
                try archive.write(from: converted)
            } catch {
                engineLog.error("archive buffer write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        rememberOverlapBuffer(converted)
    }

    /// Convert a hardware-rate buffer to 16 kHz mono. Runs on the tap thread.
    private func downsample(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError {
            engineLog.error("downsample failed: \(conversionError.localizedDescription, privacy: .public)")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    private func publishLevel(from buffer: AVAudioPCMBuffer) {
        let now = Date().timeIntervalSince1970
        guard now - lastLevelPublishAt > 0.08 else { return }
        lastLevelPublishAt = now

        guard let channels = buffer.floatChannelData else { return }
        let channel = channels[0]
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        let normalized = min(1, Double(rms) * 14)

        DispatchQueue.main.async {
            self.level = normalized
            SharedConfig.engineLevel = normalized
        }
    }

    @MainActor
    private func startTimers() {
        heartbeatTimer?.invalidate()
        commandTimer?.invalidate()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let status = self.engine.isRunning ? self.status : .inactive
            SharedConfig.markEngineAlive(status: status)
            if status != .listening {
                self.level = 0
                SharedConfig.engineLevel = 0
            }
        }

        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollCommand()
        }
    }

    private func pollCommand() {
        guard let command = SharedConfig.dictationCommand else { return }
        guard command != lastHandledCommand else { return }
        lastHandledCommand = command
        SharedConfig.dictationCommand = nil

        let ageMs = Date().timeIntervalSince1970 * 1000 - command.issuedAt
        engineLog.info("command received action=\(command.action.rawValue, privacy: .public) id=\(command.id, privacy: .public) ageMs=\(ageMs, privacy: .public)")
        switch command.action {
        case .start:
            startUtterance(id: command.id)
        case .stop:
            stopUtterance(id: command.id)
        case .deactivate:
            deactivate()
        }
    }

    private func deactivate() {
        engineLog.info("deactivate requested")
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        commandTimer?.invalidate()
        commandTimer = nil
        chunkTimer?.invalidate()
        chunkTimer = nil

        audioLock.lock()
        audioFile = nil
        archiveAudioFile = nil
        currentFileURL = nil
        archiveFileURL = nil
        currentRequestID = nil
        currentSession = nil
        currentChunkIndex = 0
        overlapBuffers = []
        overlapFrameCount = 0
        audioLock.unlock()

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        DispatchQueue.main.async {
            self.level = 0
            self.status = .inactive
            self.lastError = nil
            SharedConfig.engineStatus = .inactive
            SharedConfig.engineHeartbeatAt = 0
            SharedConfig.engineLevel = 0
            SharedConfig.engineLastError = nil
        }
    }

    private func startUtterance(id: String) {
        do {
            try startAudioSessionIfNeeded()
            guard currentRequestID == nil else {
                engineLog.info("start ignored; already recording")
                return
            }
            guard converter != nil else {
                throw NSError(
                    domain: "openwispr.engine",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Input format unavailable."]
                )
            }

            let session = ActiveDictationSession(id: id)
            let url = chunkURL(id: id, index: 0)
            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openwispr-\(id)-archive.wav")
            let file = try AVAudioFile(forWriting: url, settings: chunkFileSettings)
            let archiveFile = try AVAudioFile(forWriting: archiveURL, settings: chunkFileSettings)

            audioLock.lock()
            audioFile = file
            archiveAudioFile = archiveFile
            currentFileURL = url
            archiveFileURL = archiveURL
            currentRequestID = id
            currentSession = session
            currentChunkIndex = 0
            overlapBuffers = []
            overlapFrameCount = 0
            audioLock.unlock()

            DispatchQueue.main.async {
                self.startChunkTimer()
                self.setStatus(.listening)
            }
            engineLog.info("utterance started id=\(id, privacy: .public) targetRate=\(self.targetFormat.sampleRate, privacy: .public)")
        } catch {
            SharedConfig.completeDictation(id: id, text: nil, error: error.localizedDescription)
            DispatchQueue.main.async { self.setStatus(.armed) }
            engineLog.error("start utterance failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopUtterance(id: String) {
        DispatchQueue.main.async {
            self.chunkTimer?.invalidate()
            self.chunkTimer = nil
        }

        audioLock.lock()
        let url = currentFileURL
        let archiveURL = archiveFileURL
        let requestID = currentRequestID
        let session = currentSession
        let chunkIndex = currentChunkIndex
        audioFile = nil
        archiveAudioFile = nil
        currentFileURL = nil
        archiveFileURL = nil
        currentRequestID = nil
        currentSession = nil
        currentChunkIndex = 0
        overlapBuffers = []
        overlapFrameCount = 0
        audioLock.unlock()

        guard requestID == id, let url, let archiveURL, let session else {
            SharedConfig.completeDictation(id: id, text: nil, error: "No active dictation.")
            DispatchQueue.main.async { self.setStatus(.armed) }
            engineLog.error("stop requested with no active dictation id=\(id, privacy: .public)")
            return
        }

        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? -1
        session.enqueueChunk(index: chunkIndex, fileURL: url)
        DispatchQueue.main.async { self.setStatus(.processing) }
        engineLog.info("utterance stopped id=\(id, privacy: .public) finalChunk=\(chunkIndex, privacy: .public) fileSize=\(size, privacy: .public)")
        Task { await finalize(session: session, archiveFileURL: archiveURL, id: id) }
    }

    @MainActor
    private func startChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) { [weak self] _ in
            self?.rotateChunkIfNeeded()
        }
    }

    private var chunkInterval: TimeInterval {
        switch SharedConfig.cleanupStyle {
        case .developer, .notes:
            return 4.5
        default:
            return 3.25
        }
    }

    private func rotateChunkIfNeeded() {
        audioLock.lock()
        guard let id = currentRequestID,
              let session = currentSession,
              let finishedURL = currentFileURL else {
            audioLock.unlock()
            return
        }

        let finishedIndex = currentChunkIndex
        let nextIndex = finishedIndex + 1
        let nextURL = chunkURL(id: id, index: nextIndex)

        do {
            let nextFile = try AVAudioFile(forWriting: nextURL, settings: chunkFileSettings)
            for buffer in overlapBuffers {
                try nextFile.write(from: buffer)
            }
            audioFile = nextFile
            currentFileURL = nextURL
            currentChunkIndex = nextIndex
            audioLock.unlock()

            let size = ((try? FileManager.default.attributesOfItem(atPath: finishedURL.path))?[.size] as? NSNumber)?.intValue ?? -1
            session.enqueueChunk(index: finishedIndex, fileURL: finishedURL)
            engineLog.info("chunk rotated id=\(id, privacy: .public) finishedIndex=\(finishedIndex, privacy: .public) nextIndex=\(nextIndex, privacy: .public) fileSize=\(size, privacy: .public)")
        } catch {
            audioLock.unlock()
            engineLog.error("chunk rotation failed id=\(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func chunkURL(id: String, index: Int) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("openwispr-\(id)-chunk-\(index).wav")
    }

    private func rememberOverlapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard audioFile != nil else { return }
        guard let copy = copyBuffer(buffer) else { return }
        overlapBuffers.append(copy)
        overlapFrameCount += AVAudioFramePosition(copy.frameLength)

        let sampleRate = copy.format.sampleRate
        let maxFrames = AVAudioFramePosition(sampleRate * overlapDuration)
        while overlapFrameCount > maxFrames, !overlapBuffers.isEmpty {
            let removed = overlapBuffers.removeFirst()
            overlapFrameCount -= AVAudioFramePosition(removed.frameLength)
        }
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
            return copy
        }

        return nil
    }

    private func finalize(session: ActiveDictationSession, archiveFileURL: URL, id: String) async {
        defer { try? FileManager.default.removeItem(at: archiveFileURL) }

        await session.waitForChunks()
        let raw = session.assembler.assembledText()
        let chunkErrors = session.errors()
        if !chunkErrors.isEmpty {
            engineLog.error("chunk errors id=\(id, privacy: .public) count=\(chunkErrors.count, privacy: .public)")
        }

        do {
            let result = try await TranscriptionPipeline.finalize(rawTranscript: raw)
            SharedConfig.addTranscript(
                result.text,
                raw: result.raw,
                source: "Keyboard",
                title: "Keyboard dictation",
                audioFileURL: archiveFileURL
            )
            SharedConfig.completeDictation(id: id, text: result.text, error: nil)
            await MainActor.run { setStatus(.armed) }
            let duration = Date().timeIntervalSince(session.startedAt)
            engineLog.info("utterance finalized id=\(id, privacy: .public) rawLength=\(result.raw.count, privacy: .public) finalLength=\(result.text.count, privacy: .public) duration=\(duration, privacy: .public)")
        } catch {
            SharedConfig.completeDictation(id: id, text: nil, error: error.localizedDescription)
            await MainActor.run { setStatus(.armed) }
            engineLog.error("finalization failed id=\(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fail the in-flight request so the keyboard doesn't sit waiting on a
    /// result that will never arrive.
    private func abortActiveDictation(reason: String) {
        DispatchQueue.main.async {
            self.chunkTimer?.invalidate()
            self.chunkTimer = nil
        }

        audioLock.lock()
        let requestID = currentRequestID
        let url = currentFileURL
        let archiveURL = archiveFileURL
        audioFile = nil
        archiveAudioFile = nil
        currentFileURL = nil
        archiveFileURL = nil
        currentRequestID = nil
        currentSession = nil
        currentChunkIndex = 0
        overlapBuffers = []
        overlapFrameCount = 0
        audioLock.unlock()

        guard let requestID else { return }
        if let url { try? FileManager.default.removeItem(at: url) }
        if let archiveURL { try? FileManager.default.removeItem(at: archiveURL) }
        SharedConfig.completeDictation(id: requestID, text: nil, error: reason)
        engineLog.info("aborted active dictation id=\(requestID, privacy: .public) reason=\(reason, privacy: .public)")
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            engineLog.info("audio interruption began")
            abortActiveDictation(reason: "Audio interrupted.")
            DispatchQueue.main.async { self.setStatus(.error, error: "Audio interrupted.") }
        case .ended:
            engineLog.info("audio interruption ended; rearming")
            activate()
        @unknown default:
            break
        }
    }

    @MainActor
    private func setError(_ message: String) {
        setStatus(.error, error: message)
    }

    @MainActor
    private func setStatus(_ newStatus: EngineStatus, error: String? = nil) {
        status = newStatus
        lastError = error
        if newStatus != .listening {
            level = 0
            SharedConfig.engineLevel = 0
        }
        SharedConfig.markEngineAlive(status: newStatus)
        SharedConfig.engineLastError = error
    }
}
