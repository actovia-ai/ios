import Models
import NetworkingKit
import SwiftUI

/// The Dashboard (the desktop's Costs and Schedule tabs): the last 30 days' cost, cost by employee, and the tasks
/// waiting to run, each of which can be cancelled.
struct DashboardView: View {
    @State private var model: DashboardViewModel
    @State private var schedule = Schedule.upcoming

    enum Schedule: Hashable { case upcoming, recurring }

    init(api: PhilharmonicAPI) {
        _model = State(initialValue: DashboardViewModel(api: api))
    }

    var body: some View {
        List {
            if let costs = model.costs {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10)
                    {
                        tile(
                            Text("philharmonic:costAnalysis.kpi.totalCost"), value: Self.money(costs.totalCost),
                            hint: Self.employeesHint(costs.byAgent.count))
                        tile(
                            Text("philharmonic:costAnalysis.kpi.tokens"), value: costs.totalTokens.formatted(.number.notation(.compactName)),
                            hint: String(localized: "philharmonic:costAnalysis.kpi.tokensHint", defaultValue: "Total processed"))
                        tile(
                            Text("philharmonic:costAnalysis.kpi.employees"), value: costs.byAgent.count.formatted(),
                            hint: String(localized: "philharmonic:costAnalysis.kpi.employeesHint", defaultValue: "With recorded usage"))
                        tile(
                            Text("philharmonic:costAnalysis.kpi.conversations"), value: costs.byConversation.count.formatted(),
                            hint: String(localized: "philharmonic:costAnalysis.kpi.conversationsHint", defaultValue: "With activity"))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    PageHeader(title: Text("philharmonic:costAnalysis.header.title")) {
                        Text("philharmonic:costAnalysis.periodToggle.thirtyDays")
                    }
                }
                Section {
                    if costs.byAgent.isEmpty {
                        Text("philharmonic:costAnalysis.agentCostList.empty").foregroundStyle(.secondary)
                    }
                    ForEach(costs.byAgent.sorted { $0.cost > $1.cost }, id: \.agentId) { row in
                        let employee = model.employees[row.agentId]
                        HStack(spacing: 12) {
                            GroupAvatar(role: .employee, employee: employee)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: employee?.name ?? String(localized: "philharmonic:chat.decision.formerEmployee", defaultValue: "former employee"))
                                Text(Self.tokens(row.tokens))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(verbatim: Self.money(row.cost))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("philharmonic:costAnalysis.agentCostList.title")
                }
            }
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

    private func tile(_ title: Text, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title.font(.footnote).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(verbatim: hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
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

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(value < 1 ? 4 : 2)))
    }

    static func tokens(_ count: Int) -> String {
        let tokens = count.formatted()
        return String(localized: "philharmonic:costAnalysis.agentCostList.tokens", defaultValue: "\(tokens) tokens")
    }

    /// The catalog picks the plural form; the branch only gives the English its singular.
    static func employeesHint(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "philharmonic:costAnalysis.kpi.totalCostHint", defaultValue: "Across \(count) employee")
        }
        return String(localized: "philharmonic:costAnalysis.kpi.totalCostHint", defaultValue: "Across \(count) employees")
    }
}
