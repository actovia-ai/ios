import Foundation
import Models
import NetworkingKit
import Observation

/// The Dashboard: what the last 30 days cost, and the tasks waiting to run. Cancelling a task shows at once and comes
/// back if the computer refused it.
@MainActor @Observable
public final class DashboardViewModel {
    public private(set) var costs: PhilharmonicCosts?
    public private(set) var upcoming: [ScheduledTask] = []
    public private(set) var recurring: [ScheduledTask] = []
    public private(set) var employees: [String: Employee] = [:]
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    @ObservationIgnored private let api: PhilharmonicAPI

    public init(api: PhilharmonicAPI) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        async let costs = api.costs(days: 30)
        async let upcoming = api.upcomingTasks()
        async let recurring = api.recurringTasks()
        async let employees = api.employees()
        do {
            self.costs = try await costs
            self.upcoming = try await upcoming
            self.recurring = try await recurring
        } catch {
            guard !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
        // Names only: the figures stand without them.
        if let people = try? await employees {
            self.employees = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func cancel(_ task: ScheduledTask) async {
        let upcomingBefore = upcoming
        let recurringBefore = recurring
        upcoming.removeAll { $0.id == task.id }
        recurring.removeAll { $0.id == task.id }
        do {
            _ = try await api.cancelTask(id: task.id)
        } catch {
            upcoming = upcomingBefore
            recurring = recurringBefore
            errorMessage = error.localizedDescription
        }
    }
}
