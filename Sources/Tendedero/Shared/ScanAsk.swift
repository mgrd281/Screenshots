import Foundation

/// What an AI chat may be asked with a scanned document's covered copy,
/// in the owner's own Claude or ChatGPT app: Snapfly hands over the copy
/// and the question, and nothing is sent until the owner sends it there.
/// Each question tells the chat never to guess what is covered or cannot be
/// read, and never to fill in or correct a number.
enum ScanAsk: String, CaseIterable, Identifiable, Sendable {
    case explain, summarize, deadlines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: L("Explain the Document")
        case .summarize: L("Summarize")
        case .deadlines: L("List Deadlines and Amounts")
        }
    }

    var symbol: String {
        switch self {
        case .explain: "text.bubble"
        case .summarize: "text.badge.checkmark"
        case .deadlines: "calendar.badge.clock"
        }
    }

    /// The question as it goes into the chat after the pictures.
    var prompt: String {
        let ask = switch self {
        case .explain: L("Explain this document in simple words: what it is, who sent it and what it asks of me.")
        case .summarize: L("Summarize this document in a few short points.")
        case .deadlines: L("List every deadline and every amount in this document exactly as written, each with what it is for.")
        }
        return ask + " " + L("Parts are covered for privacy: never guess them. Never fill in or correct a number. Where something cannot be read, say so.")
    }
}
