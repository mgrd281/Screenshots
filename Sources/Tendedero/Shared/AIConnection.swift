import Combine
import Foundation

/// Whether the key kept for each assistant works, as last checked, and the
/// models it may use. Kept while Snapfly runs, so the pane asks the provider
/// once, then again only when a key changes or Check Again is chosen.
@MainActor
final class AIConnection: ObservableObject {
    static let shared = AIConnection()

    enum State: Equatable {
        case checking, works, refused
        case failed(String)
    }

    /// Nothing for a provider not checked yet.
    @Published private(set) var states: [AIProvider: State] = [:]
    @Published private(set) var models: [AIProvider: [AIModel]] = [:]
    private var tasks: [AIProvider: Task<Void, Never>] = [:]

    /// When the pane shows: a key kept but not checked since Snapfly opened.
    func checkIfNeeded(_ provider: AIProvider) {
        if states[provider] == nil, AIAccount.hasKey(provider) { check(provider) }
    }

    func check(_ provider: AIProvider) {
        tasks[provider]?.cancel()
        guard let key = AIAccount.key(for: provider) else {
            states[provider] = nil
            return
        }
        states[provider] = .checking
        tasks[provider] = Task { [weak self] in
            let state: State
            do {
                let found = try await AIRequest.models(provider, key: key)
                if !found.isEmpty, !Task.isCancelled { self?.models[provider] = found }
                state = .works
            } catch AIError.badKey {
                state = .refused
            } catch let failure as AIError {
                state = .failed(failure.message)
            } catch {
                state = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            self?.states[provider] = state
        }
    }

    /// A key removed: nothing left to check.
    func forget(_ provider: AIProvider) {
        tasks[provider]?.cancel()
        states[provider] = nil
    }
}
