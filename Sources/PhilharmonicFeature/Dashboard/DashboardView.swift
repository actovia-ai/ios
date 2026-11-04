import Charts
import Models
import NetworkingKit
import OdyKit
import SwiftUI

/// Plan monitoring and upcoming scheduled work.
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
            } header: {
                PageHeader(title: Text("philharmonic:chat.conversationList.configNav.dashboard")) {
                    EmptyView()
                }
            }
            if !model.plans.isEmpty {
                Section {
                    PlanActivityChart(plans: model.plans)
                } header: { Text("philharmonic:monitor.charts.activity") }
                Section {
                    ForEach(model.plans) { plan in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: plan.summary).font(.body.weight(.medium))
                            ProgressView(value: Double(plan.steps.filter { $0.status == .done || $0.status == .skipped }.count), total: Double(max(1, plan.steps.count)))
                            ForEach(plan.steps) { step in
                                HStack {
                                    if step.status == .done { Image(systemName: "checkmark.circle.fill") }
                                    else { Image(systemName: "circle") }
                                    Text(verbatim: step.title)
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                } header: { Text("philharmonic:monitor.pageTitle") }
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
        .readingColumn()
        .overlay {
            if model.isLoading, !model.hasLoaded { ProgressView() }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .alert(
            Text("philharmonic:schedule.toast.cancelTaskFailed"),
            isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
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
                    Text(
                        String(
                            localized: "philharmonic:schedule.recurringList.lastRun", defaultValue: "last \(time)"
                        ))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct PlanActivityChart: View {
    let plans: [GroupPlan]
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    var body: some View {
        Chart(days, id: \.self) { day in
            let count = plans.filter { plan in
                guard let date = GroupTime.date(plan.updatedAt) else { return false }
                return Calendar.current.isDate(date, inSameDayAs: day)
            }.count
            BarMark(x: .value("Date", day, unit: .day), y: .value("Plans", count))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(Text(day, format: .dateTime.month().day()))
                .accessibilityValue(Text(verbatim: count.formatted()))
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
        .frame(height: 160)
        .accessibilityLabel(Text("philharmonic:monitor.charts.activityHint"))
    }
}
