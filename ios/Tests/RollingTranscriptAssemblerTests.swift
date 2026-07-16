import Foundation

@main
struct RollingTranscriptAssemblerTests {
    static func main() {
        testOrdersChunksBeforeAssembly()
        testRemovesOverlappingBoundaryWords()
        testKeepsTechnicalTokens()
        print("RollingTranscriptAssemblerTests passed")
    }

    private static func testOrdersChunksBeforeAssembly() {
        let assembler = RollingTranscriptAssembler()
        assembler.setChunk(index: 1, text: "second chunk")
        assembler.setChunk(index: 0, text: "first chunk")
        assertEqual(assembler.assembledText(), "first chunk second chunk")
    }

    private static func testRemovesOverlappingBoundaryWords() {
        let assembler = RollingTranscriptAssembler()
        assembler.setChunk(index: 0, text: "I can meet Saturday around noon")
        assembler.setChunk(index: 1, text: "around noon if that works")
        assertEqual(assembler.assembledText(), "I can meet Saturday around noon if that works")
    }

    private static func testKeepsTechnicalTokens() {
        let assembler = RollingTranscriptAssembler()
        assembler.setChunk(index: 0, text: "open src slash components")
        assembler.setChunk(index: 1, text: "components slash button dot tsx and run dash dash force")
        assertEqual(
            assembler.assembledText(),
            "open src slash components slash button dot tsx and run dash dash force"
        )
    }

    private static func assertEqual(_ actual: String, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        guard actual == expected else {
            fputs("Assertion failed at \(file):\(line)\nexpected: \(expected)\nactual:   \(actual)\n", stderr)
            exit(1)
        }
    }
}
