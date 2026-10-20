import SwiftUI
import WidgetKit
import WidgetKitShared

struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.yancey.actovia.ask-control") {
            ControlWidgetButton(action: AskActoviaIntent()) {
                Label("ios:widget.ask.title", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .displayName("ios:widget.ask.title")
    }
}
