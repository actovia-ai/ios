import Models
import NetworkingKit
import SwiftUI

/// The Dashboard (the desktop's Schedule tab): the tasks waiting to run, each of which can be cancelled.
struct DashboardView: View {
    @State private var model: DashboardViewModel
    @State private var schedule = Schedule.upcoming

    enum Schedule: Hashable { case upcoming, recurring }

    init(api: PhilharmonicAPI) {
        _model = State(initialValue: DashboardViewModel(api: api))
    }

    var body: some View {
        List {
            Section {
                let tasks = schedule == .upcoming ? model.upcoming : model.recurring
                if tasks.isEmpty, model.hasLoaded {
                    if schedule == .upcoming {
                        Text("philharmonic:schedule.upcomingList.empty").foregroundStyle(.secondary)
                    } else {
                        Text("philharmonic:schedule.recurringList.empty").foregroundStyle(.secondary)
                    }
                }
                ForEach(tasks) { task in
                    taskRow(task)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.cancel(task) }
                            } label: {
                                Label("philharmonic:schedule.taskCard.cancelAria", systemImage: "xmark.circle")
                            }
                        }
                }
            } header: {
                Picker(selection: $schedule) {
                    Text("philharmonic:schedule.tab.upcomingTrigger").tag(Schedule.upcoming)
                    Text("philharmonic:schedule.tab.recurringTrigger").tag(Schedule.recurring)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .textCase(nil)
                .padding(.bottom, 4)
            }
        }
        .overlay {
            if model.isLoading, !model.hasLoaded { ProgressView() }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .alert(
            Text("philharmonic:schedule.toast.cancelTaskFailed"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("ios:app.alert.ok") { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }

    private func taskRow(_ task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: task.title).font(.body.weight(.medium))
            Group {
                if let runAt = GroupTime.date(task.runAt) {
                    Text(runAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                } else if let cron = task.cronExpression {
                    Text(verbatim: cron).monospaced()
                }
                if let last = GroupTime.date(task.lastRunAt) {
                    let time = last.formatted(.dateTime.month().day().hour().minute())
                    Text(String(localized: "philharmonic:schedule.recurringList.lastRun", defaultValue: "last \(time)"))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
