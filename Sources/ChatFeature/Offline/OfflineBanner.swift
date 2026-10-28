import SwiftUI

/// The thin band under the title while the computer does not answer: "Offline · Last synced 5 min ago". Tapping it
/// asks again (`retry`). One element for VoiceOver, with the retry as its hint.
struct OfflineBanner: View {
    let lastSyncedAt: Date?
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(verbatim: Self.text(lastSyncedAt: lastSyncedAt, now: .now, locale: .current))
                    .font(.footnote)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:offline.retryHint"))
        .transition(.opacity)
    }

    /// "Offline · Last synced 5 min ago", or just "Offline" when nothing was ever read from the computer.
    nonisolated static func text(lastSyncedAt: Date?, now: Date, locale: Locale) -> String {
        guard let lastSyncedAt else {
            return String(localized: "ios:offline.bannerNoSync", defaultValue: "Offline", comment: "The banner while the computer does not answer and nothing was ever read from it.")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .numeric
        let relative = formatter.localizedString(for: lastSyncedAt, relativeTo: now)
        return String(localized: "ios:offline.banner", defaultValue: "Offline · Last synced \(relative)", comment: "The banner while the computer does not answer. %@ is how long ago the data was read, e.g. “5 min. ago”.")
    }
}
