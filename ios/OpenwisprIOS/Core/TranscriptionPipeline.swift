import Foundation
import os

private let pipelineLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "TranscriptionPipeline")

struct TranscriptionResult {
    let raw: String
    let text: String
}

enum TranscriptionPipelineError: LocalizedError {
    case missingAPIKey
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Groq API key in Settings."
        case .noSpeech:
            return "No speech detected."
        }
    }
}

enum TranscriptionPipeline {
    static func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        let totalStart = Date()
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.intValue ?? -1
        pipelineLog.info("transcribe start fileSize=\(size, privacy: .public) model=\(SharedConfig.transcribeModel, privacy: .public) language=\(SharedConfig.transcribeLanguage, privacy: .public)")

        let sttStart = Date()
        let raw = try await transcribeRaw(fileURL: fileURL)
        let sttMs = Date().timeIntervalSince(sttStart) * 1000
        pipelineLog.info("raw transcript received length=\(raw.count, privacy: .public) sttMs=\(sttMs, privacy: .public)")

        let result = try await finalize(rawTranscript: raw)
        let totalMs = Date().timeIntervalSince(totalStart) * 1000
        pipelineLog.info("transcribe complete finalLength=\(result.text.count, privacy: .public) sttMs=\(sttMs, privacy: .public) totalMs=\(totalMs, privacy: .public)")

        return result
    }

    static func transcribeRaw(fileURL: URL) async throws -> String {
        guard let apiKey = SharedConfig.groqApiKey, !apiKey.isEmpty else {
            pipelineLog.error("missing API key")
            throw TranscriptionPipelineError.missingAPIKey
        }

        let raw = try await GroqClient.transcribe(
            fileURL: fileURL,
            apiKey: apiKey,
            model: SharedConfig.transcribeModel,
            language: SharedConfig.transcribeLanguage,
            vocabulary: SharedConfig.vocabulary
        )
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pipelineLog.error("no speech detected")
            throw TranscriptionPipelineError.noSpeech
        }
        return trimmed
    }

    static func finalize(rawTranscript: String) async throws -> TranscriptionResult {
        let totalStart = Date()
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pipelineLog.error("no speech detected")
            throw TranscriptionPipelineError.noSpeech
        }

        let final: String
        var cleanupMs: Double = 0
        if SharedConfig.cleanupEnabled {
            guard let apiKey = SharedConfig.groqApiKey, !apiKey.isEmpty else {
                pipelineLog.error("missing API key")
                throw TranscriptionPipelineError.missingAPIKey
            }
            pipelineLog.info("cleanup start model=\(SharedConfig.cleanupModel, privacy: .public)")
            let cleanupStart = Date()
            final = (try? await GroqClient.cleanup(
                text: trimmed,
                apiKey: apiKey,
                model: SharedConfig.cleanupModel,
                systemPrompt: SharedConfig.activeCleanupPrompt,
                vocabulary: SharedConfig.vocabulary
            )) ?? trimmed
            cleanupMs = Date().timeIntervalSince(cleanupStart) * 1000
        } else {
            final = trimmed
        }
        let totalMs = Date().timeIntervalSince(totalStart) * 1000
        pipelineLog.info("finalize complete rawLength=\(trimmed.count, privacy: .public) finalLength=\(final.count, privacy: .public) cleanupMs=\(cleanupMs, privacy: .public) totalMs=\(totalMs, privacy: .public)")

        return TranscriptionResult(
            raw: trimmed,
            text: final.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
