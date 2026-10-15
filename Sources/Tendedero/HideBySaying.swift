import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Hide Part, told in words: "everything but the amount and the date", or
/// "the customer's name". Apple Intelligence picks the lines of text that
/// match, on this Mac. Without it, the lines that contain the words typed
/// are picked. Either way the boxes show in Hide Part before anything is
/// kept, and a click on one shows it again.
enum HideBySaying {
    enum Outcome {
        /// The lines to hide, by their place in the list given.
        case lines([Int])
        /// Apple Intelligence cannot answer here, so the words were matched.
        case matched([Int])
    }

    /// Whether a sentence is understood, or only words are matched.
    static var understandsSentences: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    static func lines(toHide request: String, in lines: [String]) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), let chosen = await intelligently(request, lines) {
            return .lines(chosen)
        }
        #endif
        return .matched(matching(request, lines))
    }

    /// Each part typed between commas, found in a line, hides that line.
    static func matching(_ request: String, _ lines: [String]) -> [Int] {
        let parts = request.components(separatedBy: CharacterSet(charactersIn: ",،;\n"))
            .map { TextIndex.fold($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return [] }
        return lines.indices.filter { i in
            let line = TextIndex.fold(lines[i])
            return parts.contains { line.contains($0) }
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func intelligently(_ request: String, _ lines: [String]) async -> [Int]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, !lines.isEmpty else { return nil }
        let instructions = """
            You help hide private parts of a screenshot before it is shared. \
            You get the screenshot's lines of text, numbered, and what the \
            user wants hidden. They may say what to hide, or what to keep and \
            hide the rest, in any language. Answer with the numbers of the \
            lines to hide, separated by commas, and nothing else. Answer none \
            when no line matches.
            """
        // A screenful of text, kept within what the model reads at once.
        let shown = lines.prefix(150).enumerated()
            .map { "\($0.offset + 1): \($0.element.prefix(80))" }
            .joined(separator: "\n")
        let prompt = "Lines of text:\n\(shown)\n\nWhat to hide: \(request.prefix(300))"
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt, options: GenerationOptions(temperature: 0, maximumResponseTokens: 400))
            let numbers = response.content
                .split { !$0.isNumber }
                .compactMap { Int($0) }
                .map { $0 - 1 }
                .filter { lines.indices.contains($0) }
            return Array(Set(numbers)).sorted()
        } catch {
            log.error("Could not choose what to hide: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    #endif
}
