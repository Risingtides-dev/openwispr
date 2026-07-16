import Foundation

final class RollingTranscriptAssembler {
    private let lock = NSLock()
    private var chunks: [Int: String] = [:]

    func setChunk(index: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        chunks[index] = trimmed
        lock.unlock()
    }

    func assembledText() -> String {
        lock.lock()
        let ordered = chunks.keys.sorted().compactMap { chunks[$0] }
        lock.unlock()

        return ordered.reduce("") { partial, next in
            Self.merge(partial, next)
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func merge(_ left: String, _ right: String) -> String {
        let leftWords = words(in: left)
        let rightWords = words(in: right)

        guard !leftWords.isEmpty else { return rightWords.joined(separator: " ") }
        guard !rightWords.isEmpty else { return leftWords.joined(separator: " ") }

        let maxOverlap = min(14, leftWords.count, rightWords.count)
        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let leftTail = leftWords.suffix(overlap).map(normalize)
                let rightHead = rightWords.prefix(overlap).map(normalize)
                if leftTail == rightHead {
                    return (leftWords + rightWords.dropFirst(overlap)).joined(separator: " ")
                }
            }
        }

        return (leftWords + rightWords).joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func normalize(_ token: String) -> String {
        token
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}"))
            .lowercased()
    }
}
