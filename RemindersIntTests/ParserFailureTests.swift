import Foundation
import FoundationModels
import Testing
@testable import RemindersInt

/// Step 8b: only a missing or unsupported model switches to simplified mode.
@MainActor
struct ParserFailureTests {
    /// Counts the calls and throws the given error each time.
    final class FailingGenerator: @unchecked Sendable {
        let error: any Error
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.withLock { count } }

        init(_ error: any Error) { self.error = error }

        func generate(_ instructions: String, _ text: String) async throws -> GeneratedCapture {
            lock.withLock { count += 1 }
            throw error
        }
    }

    private func parser(throwing error: any Error) -> (ParserService, FailingGenerator) {
        let failing = FailingGenerator(error)
        let parser = ParserService(systemAvailability: { true }, generator: { try await failing.generate($0, $1) })
        return (parser, failing)
    }

    private static let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    @Test func transientErrorIsRetriedOnceThenFallsBack() async {
        let (parser, failing) = parser(throwing: LanguageModelSession.GenerationError.decodingFailure(Self.context))
        let parsed = await parser.parse("Rappelle-moi d'appeler Karim demain à 10h")
        #expect(failing.calls == 2)
        #expect(parsed.engine == .fallback)
        #expect(parsed.intent == .reminder)
        // The next sentence still tries the model.
        #expect(!parser.generationFailed)
        #expect(parser.isModelAvailable)
        _ = await parser.parse("Il faut que je finisse le DM")
        #expect(failing.calls == 4)
    }

    @Test func timeoutIsTransient() async {
        let (parser, failing) = parser(throwing: URLError(.timedOut))
        _ = await parser.parse("Séance faite")
        #expect(failing.calls == 2)
        #expect(!parser.generationFailed)
    }

    @Test func missingAssetsSwitchToSimplifiedMode() async {
        let (parser, failing) = parser(throwing: LanguageModelSession.GenerationError.assetsUnavailable(Self.context))
        let parsed = await parser.parse("Rappelle-moi d'appeler Karim demain à 10h")
        #expect(failing.calls == 1)
        #expect(parsed.engine == .fallback)
        #expect(parser.generationFailed)
        #expect(!parser.isModelAvailable)
        // Simplified mode: the model is not called any more.
        _ = await parser.parse("Il faut que je finisse le DM")
        #expect(failing.calls == 1)
    }

    @Test func classification() {
        #expect(ParserService.isPermanent(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(Self.context)))
        #expect(!ParserService.isPermanent(LanguageModelSession.GenerationError.guardrailViolation(Self.context)))
        #expect(!ParserService.isPermanent(LanguageModelSession.GenerationError.rateLimited(Self.context)))
        // Simulator without Apple Intelligence: generic error wrapping the model manager's.
        let manager = NSError(domain: "ModelManagerServices.ModelManagerError", code: 1026)
        let wrapped = NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1, userInfo: [NSMultipleUnderlyingErrorsKey: [manager]])
        #expect(ParserService.isPermanent(wrapped))
    }
}
