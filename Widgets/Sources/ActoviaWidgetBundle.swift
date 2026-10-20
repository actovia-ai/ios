import SwiftUI
import WidgetKit

@main
struct ActoviaWidgetBundle: WidgetBundle {
    var body: some Widget {
        AskWidget()
        TodayAccessoryWidget()
        AskControl()
    }
}
