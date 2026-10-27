import Foundation
import Models
import NetworkingKit
import Observation

/// The Dashboard: the tasks waiting to run (the desktop's Schedule tab; there is no Costs page). Cancelling a task
/// shows at once and comes back if the computer refused it.
@MainActor @Observable
public final class DashboardViewModel {
    public private(set) var upcoming: [ScheduledTask] = []
    public private(set) var recurring: [ScheduledTask] = []
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
        async let upcoming = api.upcomingTasks()
        async let recurring = api.recurringTasks()
        do {
            self.upcoming = try await upcoming
            self.recurring = try await recurring
        } catch {
            guard !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
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
