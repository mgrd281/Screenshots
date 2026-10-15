import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Hide Part, told in words: "everything but the amount and the date", or
/// "the customer's name". Apple Intelligence picks the lines, or just the
/// words in them, on this Mac. Without it, the words typed are found. Either
/// way the boxes show in Hide Part before anything is kept, and a click on
/// one shows it again.
enum HideBySaying {
    /// Something to hide: a whole line, or only some words in it.
    struct Piece {
        /// Its place in the list of lines given.
        let line: Int
        /// The words to hide in it; nil hides the whole line.
        let words: String?
    }

    enum Outcome {
        /// Chosen by Apple Intelligence.
        case understood([Piece])
        /// Apple Intelligence cannot answer here, so the words were found.
        case matched([Piece])
    }

    /// Whether a sentence is understood, or only words are found.
    static var understandsSentences: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    static func pieces(toHide request: String, in lines: [String]) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), let chosen = await intelligently(request, lines) {
            return .understood(chosen)
        }
        #endif
        return .matched(matching(request, lines))
    }

    /// Each part typed between commas, wherever a line has it.
    static func matching(_ request: String, _ lines: [String]) -> [Piece] {
        let parts = request.components(separatedBy: CharacterSet(charactersIn: ",،;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var pieces: [Piece] = []
        for (i, line) in lines.enumerated() {
            for part in parts where line.range(of: part, options: insensitive) != nil {
                pieces.append(Piece(line: i, words: part))
            }
        }
        return pieces
    }

    /// Rechnung and RECHNUNG, café and cafe, are the same words.
    static let insensitive: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// Reads the model's answer: a line's number alone, or its number, a
    /// colon and the words. Numbers listed on one row each count.
    static func parse(_ answer: String, lines count: Int) -> [Piece] {
        var pieces: [Piece] = []
        for row in answer.split(whereSeparator: \.isNewline) {
            let row = String(row)
            if let colon = row.firstIndex(of: ":"),
               let n = Int(String(row[..<colon].filter { $0.isASCII && $0.isNumber })) {
                let words = row[row.index(after: colon)...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»'`").union(.whitespaces))
                pieces.append(Piece(line: n - 1, words: words.isEmpty ? nil : words))
            } else {
                for number in row.split(whereSeparator: { !($0.isASCII && $0.isNumber) }) {
                    if let n = Int(number) { pieces.append(Piece(line: n - 1, words: nil)) }
                }
            }
        }
        return pieces.filter { $0.line >= 0 && $0.line < count }
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func intelligently(_ request: String, _ lines: [String]) async -> [Piece]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, !lines.isEmpty else { return nil }
        let instructions = """
            You help hide private parts of a screenshot before it is shared. \
            You get the screenshot's lines of text, numbered, and what the \
            user wants hidden. They may say what to hide, or what to keep and \
            hide the rest, in any language. Answer one item per row. To hide \
            a whole line, write its number. To hide only some words of a \
            line, write its number, a colon and those words exactly as they \
            appear in it. Write nothing else. Answer none when nothing \
            matches. For example:
            3
            5: Ahmed Ali
            7: DE89 3704 0044 0532 0130 00
            """
        // A screenful of text, kept within what the model reads at once.
        let shown = lines.prefix(150).enumerated()
            .map { "\($0.offset + 1): \($0.element.prefix(80))" }
            .joined(separator: "\n")
        let prompt = "Lines of text:\n\(shown)\n\nWhat to hide: \(request.prefix(300))"
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt, options: GenerationOptions(temperature: 0, maximumResponseTokens: 600))
            return parse(response.content, lines: min(lines.count, 150))
        } catch {
            log.error("Could not choose what to hide: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    #endif
}
