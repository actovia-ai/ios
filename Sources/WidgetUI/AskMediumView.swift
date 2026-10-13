import OdyKit
import SwiftUI
import WidgetKit
import WidgetKitShared

/// Home Screen, medium, as Claude's widget: the Ask capsule and four round buttons under it — a photo, a word, Health
/// and the latest chat. Nothing of the day's numbers or the chats' titles is drawn here (the Lock Screen keeps the
/// numbers): a glance shows what to do, not what was.
public struct AskMediumView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let calendar: Calendar

    public init(snapshot: WidgetSnapshot, date: Date, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        let ink = WidgetInk.color(at: date, calendar: calendar)
        VStack(spacing: 0) {
            Link(destination: DeepLink.newChat(prompt: nil).url) { AskCapsule(ink: ink) }
            // The buttons centred in what is left under the capsule, not pressed to the bottom edge.
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(WidgetAction.all(latest: snapshot.recentChats.first)) { action in
                    WidgetActionCircle(action: action, ink: ink, diameter: 56)
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .widgetURL(DeepLink.newChat(prompt: nil).url)
    }
}
