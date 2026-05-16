import Foundation
import AVFoundation
import UIKit

@MainActor
final class FlowSession: ObservableObject {
    static let shared = FlowSession()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var level: Double = 0
    @Published private(set) var expiresAt: Date?
    @Published var lastTranscript: String = ""
    @Published var errorMessage: String?

    private var engine: AVAudioEngine?
    private var inputFormat: AVAudioFormat?
    private var currentFile: AVAudioFile?
    private var currentFileURL: URL?
    private var currentUtteranceCounter: Int = 0

    private let sessionDuration: TimeInterval = 15 * 60
    private var expiryTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func startSession() {
        guard !isActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])

            let newEngine = AVAudioEngine()
            let input = newEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                try? session.setActive(false)
                errorMessage = "No live audio input. Force-quit any app holding the mic and retry."
                return
            }

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                Task { @MainActor in self?.handle(buffer: buffer) }
            }

            newEngine.prepare()
            try newEngine.start()

            engine = newEngine
            inputFormat = format
            isActive = true
            let expiry = Date().addingTimeInterval(sessionDuration)
            expiresAt = expiry
            FlowSessionState.sessionActive = true
            FlowSessionState.sessionExpiresAt = expiry
            FlowSessionState.errorMessage = nil

            registerHandlers()
            beginBackgroundTask()

            expiryTimer = Timer.scheduledTimer(withTimeInterval: sessionDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stopSession() }
            }
        } catch {
            errorMessage = "Start session: \(error.localizedDescription)"
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func stopSession() {
        unregisterHandlers()
        expiryTimer?.invalidate()
        expiryTimer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        inputFormat = nil
        currentFile = nil
        if let url = currentFileURL { try? FileManager.default.removeItem(at: url) }
        currentFileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
        isRecording = false
        level = 0
        expiresAt = nil
        FlowSessionState.sessionActive = false
        FlowSessionState.sessionExpiresAt = nil
        FlowSessionState.utteranceInProgress = false
        DarwinNotify.post(FlowSessionState.DarwinNotification.sessionEnded)
        endBackgroundTask()
    }

    private func handle(buffer: AVAudioPCMBuffer) {
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
                level = max(0, min(1, Double((db + 50) / 50)))
            }
        }
        if isRecording, let file = currentFile {
            try? file.write(from: buffer)
        }
    }

    private func markUtteranceStart() {
        guard isActive, !isRecording, let format = inputFormat else { return }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("openwispr-utt-\(UUID().uuidString).wav")
            currentFile = try AVAudioFile(forWriting: url, settings: format.settings)
            currentFileURL = url
            currentUtteranceCounter = FlowSessionState.utteranceCounter + 1
            FlowSessionState.utteranceCounter = currentUtteranceCounter
            FlowSessionState.utteranceInProgress = true
            isRecording = true
            DarwinNotify.post(FlowSessionState.DarwinNotification.utteranceAck)
        } catch {
            errorMessage = "Open utterance file: \(error.localizedDescription)"
        }
    }

    private func markUtteranceStop() {
        guard isActive, isRecording, let url = currentFileURL else { return }
        isRecording = false
        FlowSessionState.utteranceInProgress = false
        currentFile = nil
        currentFileURL = nil
        let counter = currentUtteranceCounter
        Task { await transcribe(fileURL: url, counter: counter) }
    }

    private func transcribe(fileURL: URL, counter: Int) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiKey = Secrets.groqApiKey
        guard !apiKey.isEmpty, apiKey != "gsk_REPLACE_ME" else {
            await report(error: "Set Secrets.groqApiKey in OpenwisprIOS/Secrets.swift.")
            return
        }
        do {
            let raw = try await GroqClient.transcribe(
                fileURL: fileURL,
                apiKey: apiKey,
                model: SharedConfig.transcribeModel,
                vocabulary: SharedConfig.vocabulary
            )
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await report(error: "No speech detected.")
                return
            }
            let final: String
            if SharedConfig.cleanupEnabled {
                final = (try? await GroqClient.cleanup(
                    text: trimmed,
                    apiKey: apiKey,
                    model: SharedConfig.cleanupModel,
                    systemPrompt: SharedConfig.cleanupPrompt,
                    vocabulary: SharedConfig.vocabulary
                )) ?? trimmed
            } else {
                final = trimmed
            }
            await MainActor.run {
                FlowSessionState.latestTranscript = final
                FlowSessionState.latestTranscriptCounter = counter
                lastTranscript = final
            }
            DarwinNotify.post(FlowSessionState.DarwinNotification.transcriptReady)
        } catch {
            await report(error: error.localizedDescription)
        }
    }

    private func report(error message: String) async {
        await MainActor.run {
            errorMessage = message
            FlowSessionState.errorMessage = message
        }
        DarwinNotify.post(FlowSessionState.DarwinNotification.transcriptReady)
    }

    private func registerHandlers() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        DarwinNotify.observe(FlowSessionState.DarwinNotification.startUtterance, observer: observer) { _, observer, _, _, _ in
            guard let observer else { return }
            let session = Unmanaged<FlowSession>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in session.markUtteranceStart() }
        }
        DarwinNotify.observe(FlowSessionState.DarwinNotification.stopUtterance, observer: observer) { _, observer, _, _, _ in
            guard let observer else { return }
            let session = Unmanaged<FlowSession>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in session.markUtteranceStop() }
        }
    }

    private func unregisterHandlers() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        DarwinNotify.remove(FlowSessionState.DarwinNotification.startUtterance, observer: observer)
        DarwinNotify.remove(FlowSessionState.DarwinNotification.stopUtterance, observer: observer)
    }

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FlowSession") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
