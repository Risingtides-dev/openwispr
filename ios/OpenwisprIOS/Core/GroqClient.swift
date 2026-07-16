import Foundation
import os

private let groqLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "GroqClient")

enum GroqError: LocalizedError {
    case http(Int, String)
    case decode

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            let snippet = body.count > 200 ? String(body.prefix(200)) + "..." : body
            return "Groq \(code): \(snippet)"
        case .decode:
            return "Groq returned an unexpected response."
        }
    }
}

enum GroqClient {
    private static let base = URL(string: "https://api.groq.com/openai/v1")!

    static func transcribe(
        fileURL: URL,
        apiKey: String,
        model: String,
        language: String,
        vocabulary: String
    ) async throws -> String {
        let url = base.appendingPathComponent("audio/transcriptions")
        let boundary = "openwispr-\(UUID().uuidString)"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) {
            if let d = s.data(using: .utf8) { body.append(d) }
        }
        let audio = try Data(contentsOf: fileURL)
        groqLog.info("stt request body audioBytes=\(audio.count, privacy: .public) model=\(model, privacy: .public)")

        let fileName = "audio.\(fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension)"
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n")
        body.append(audio)
        append("\r\n")

        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        field("model", model)
        field("response_format", "text")
        field("temperature", "0")
        let languageCode = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !languageCode.isEmpty {
            field("language", languageCode)
        }
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty {
            field("prompt", "Glossary of terms that may appear: \(vocab).")
        }
        append("--\(boundary)--\r\n")
        req.httpBody = body

        let started = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let elapsedMs = Date().timeIntervalSince(started) * 1000
        try check(resp: resp, data: data)
        groqLog.info("stt response bytes=\(data.count, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)")
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func cleanup(
        text: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        vocabulary: String
    ) async throws -> String {
        let url = base.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = vocab.isEmpty
            ? systemPrompt
            : systemPrompt + "\n\nKNOWN VOCABULARY — preserve these exact spellings and fix obvious mistranscriptions to match them: \(vocab)"

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "<transcript>\(text)</transcript>"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        groqLog.info("cleanup request inputChars=\(text.count, privacy: .public) model=\(model, privacy: .public)")

        let started = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let elapsedMs = Date().timeIntervalSince(started) * 1000
        try check(resp: resp, data: data)
        groqLog.info("cleanup response bytes=\(data.count, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)")

        struct Resp: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let parsed = try? JSONDecoder().decode(Resp.self, from: data),
              let content = parsed.choices.first?.message.content else {
            throw GroqError.decode
        }
        var out = content.trimmingCharacters(in: .whitespacesAndNewlines)
        out = out.replacingOccurrences(of: "^<transcript>\\s*", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s*</transcript>$", with: "", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func check(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw GroqError.decode }
        guard (200..<300).contains(http.statusCode) else {
            throw GroqError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a": return "audio/m4a"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }
}
