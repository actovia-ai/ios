import Foundation
import SwiftUI

/// A display projection of the attachment, never a replacement for its original wire data.
enum HealthContextDetails {
    struct Row: Equatable {
        let label: String
        let value: String
    }
    struct Section: Equatable {
        let title: String
        let rows: [Row]
    }

    private static let labels: [String: LocalizedStringResource] = [
        "asleepMin": "chat:health.field.asleep", "asleepHours": "chat:health.field.asleep",
        "baselineMin": "chat:health.field.asleep", "deepMin": "chat:health.field.deep",
        "coreMin": "chat:health.field.core", "remMin": "chat:health.field.rem",
        "awakeMin": "chat:health.field.awake", "bedtime": "chat:health.field.inBed",
        "wake": "chat:health.field.wake", "steps": "chat:health.field.steps",
        "stepGoal": "chat:health.field.steps", "activeKcal": "chat:health.field.activeEnergy",
        "kcalGoal": "chat:health.field.activeEnergy", "exerciseMin": "chat:health.field.exercise",
        "standHours": "chat:health.field.stand", "hrvMs": "chat:health.field.hrv",
        "hrvBaselineMs": "chat:health.field.hrv", "restingHr": "chat:health.field.restingHr",
        "restingHrBaseline": "chat:health.field.restingHr", "respRate": "chat:health.field.respRate",
        "weightKg": "chat:health.field.weight", "weightTrend30d": "chat:health.field.weightTrend",
        "waterCups": "chat:health.field.water", "mood": "chat:health.field.mood",
        "level": "chat:health.field.level", "workouts": "chat:health.field.workouts",
    ]
    private static let order = [
        "asleepMin", "asleepHours", "deepMin", "coreMin", "remMin", "awakeMin", "bedtime", "wake",
        "steps", "activeKcal", "exerciseMin", "standHours", "workouts", "level", "hrvMs", "restingHr",
        "respRate", "waterCups", "weightKg", "weightTrend30d", "mood",
    ]

    static func sections(json: String) -> [Section] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return [] }
        if let category = object["category"] as? String, let days = object["days"] as? [[String: Any]] {
            return days.compactMap { day in
                var values = day["values"] as? [String: Any] ?? [:]
                values["wake"] = day["wake"]
                values["mood"] = day["mood"]
                let rows = rows(values)
                guard !rows.isEmpty else { return nil }
                return Section(
                    title:
                        "\(HealthContextCard.categoryTitle(category)) · \(dayLabel(day["date"] as? String ?? ""))",
                    rows: rows)
            }
        }
        return ["sleep", "activity", "recovery", "body"].compactMap { category in
            guard let values = object[category] as? [String: Any] else { return nil }
            let rows = rows(values)
            return rows.isEmpty
                ? nil : Section(title: HealthContextCard.categoryTitle(category), rows: rows)
        }
    }

    private static func rows(_ values: [String: Any]) -> [Row] {
        order.compactMap { key in
            guard let raw = values[key], !(raw is NSNull), let label = labels[key],
                let value = value(raw, key: key), !value.isEmpty
            else { return nil }
            var rendered = value
            let baseline: String? = [
                "asleepMin": "baselineMin", "steps": "stepGoal", "activeKcal": "kcalGoal",
                "hrvMs": "hrvBaselineMs", "restingHr": "restingHrBaseline",
            ][key]
            if let baseline, let number = values[baseline], let usual = self.value(number, key: key) {
                // Reuse the desktop's localized comparison wording and unit placement.
                rendered = String(
                    format: localized("chat:health.withUsual", fallback: "%@ · usual %@"), value, usual)
            }
            return Row(label: String(localized: label), value: rendered)
        }
    }

    private static func value(_ raw: Any, key: String) -> String? {
        if let number = raw as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                return nil
            }
            let n = number.doubleValue
            if (key.hasSuffix("Min") || key == "asleepHours") && (n < 0 || n > 527_040) { return nil }
            let formatted = n.formatted(.number.precision(.fractionLength(0...1)))
            if key.hasSuffix("Min") {
                return Duration.seconds(n * 60).formatted(
                    .units(allowed: [.hours, .minutes], width: .abbreviated))
            }
            if key == "asleepHours" {
                return Duration.seconds(n * 3600).formatted(
                    .units(allowed: [.hours, .minutes], width: .abbreviated))
            }
            let unitKey =
                switch key {
                case "activeKcal", "kcalGoal": "chat:health.kcal"
                case "hrvMs", "hrvBaselineMs": "chat:health.ms"
                case "restingHr", "restingHrBaseline": "chat:health.bpm"
                case "respRate": "chat:health.perMin"
                case "weightKg", "weightTrend30d": "chat:health.kg"
                case "waterCups": if n == 1 { "chat:health.cups_one" } else { "chat:health.cups_other" }
                case "standHours": if n == 1 { "chat:health.hours_one" } else { "chat:health.hours_other" }
                default: ""
                }
            return unitKey.isEmpty
                ? formatted
                : String(
                    format: localized(
                        unitKey,
                        fallback: [
                            "chat:health.kcal": "%@ kcal", "chat:health.ms": "%@ ms", "chat:health.bpm": "%@ bpm",
                            "chat:health.perMin": "%@/min", "chat:health.kg": "%@ kg",
                            "chat:health.cups_one": "%@ cup", "chat:health.cups_other": "%@ cups",
                            "chat:health.hours_one": "%@ hr", "chat:health.hours_other": "%@ hrs",
                        ][unitKey]), formatted)
        }
        if let string = raw as? String {
            if key == "mood" { return localized("chat:health.mood.\(string)", fallback: string) }
            if key == "level" { return localized("chat:health.level.\(string)", fallback: string) }
            return string
        }
        if key == "workouts", let workouts = raw as? [[String: Any]] {
            return workouts.compactMap { workout in
                guard let type = workout["type"] as? String else { return nil }
                let duration = workout["minutes"].flatMap { value($0, key: "exerciseMin") }
                let energy = workout["kcal"].flatMap { value($0, key: "activeKcal") }
                return [type, duration, energy].compactMap { $0 }.joined(separator: " · ")
            }.joined(separator: "\n")
        }
        return nil
    }

    private static func localized(_ key: String, fallback: String? = nil) -> String {
        let result = String(localized: String.LocalizationValue(key))
        return result == key ? fallback ?? key : result
    }

    private static func dayLabel(_ string: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: string) else { return string }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
