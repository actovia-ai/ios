import Foundation
import Models
import NetworkingKit
import Observation

/// The seam between the view model and the network, so tests can answer out of order.
public protocol ChatSearchService: Sendable {
    func search(query: String) async throws -> [ChatSearchResult]
}

public struct APIChatSearchService: ChatSearchService {
    private let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func search(query: String) async throws -> [ChatSearchResult] {
        try await apiClient.get("/api/v1/chat/search", query: [URLQueryItem(name: "query", value: query)])
    }
}

@MainActor
@Observable
public final class ChatSearchViewModel {
    public enum Phase: Equatable {
        case idle
        case results([ChatSearchResult])
        case empty
        case failed(String)
    }

    public private(set) var query = ""
    public private(set) var phase: Phase = .idle
    public private(set) var isSearching = false

    /// True when the trimmed query is non-empty: the sidebar shows results instead of Recents.
    public var hasQuery: Bool { !trimmedQuery.isEmpty }

    private let service: any ChatSearchService
    private let debounce: Duration
    /// Bumped by every new query and by `reset()`. A response applies only if it is still the current one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(service: any ChatSearchService, debounce: Duration = .milliseconds(300)) {
        self.service = service
        self.debounce = debounce
    }

    public convenience init(apiClient: APIClient, debounce: Duration = .milliseconds(300)) {
        self.init(service: APIChatSearchService(apiClient: apiClient), debounce: debounce)
    }

    public func updateQuery(_ text: String) {
        guard text != query else { return }
        query = text
        run()
    }

    /// Runs the current query again (the Retry button after a failure).
    public func retry() {
        guard hasQuery else { return }
        run()
    }

    /// Leaves search: cancels work, forgets the query and the results.
    public func reset() {
        task?.cancel()
        task = nil
        generation += 1
        query = ""
        phase = .idle
        isSearching = false
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func run() {
        task?.cancel()
        generation += 1
        let generation = generation
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            task = nil
            phase = .idle
            isSearching = false
            return
        }
        isSearching = true
        let debounce = debounce
        task = Task { [weak self] in
            do { try await Task.sleep(for: debounce) } catch { return }
            await self?.perform(trimmed, generation: generation)
        }
    }

    private func perform(_ trimmed: String, generation: Int) async {
        do {
            let results = try await service.search(query: trimmed)
            guard generation == self.generation else { return }
            phase = results.isEmpty ? .empty : .results(results)
            isSearching = false
        } catch {
            guard generation == self.generation else { return }
            isSearching = false
            if isCancellation(error) { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
