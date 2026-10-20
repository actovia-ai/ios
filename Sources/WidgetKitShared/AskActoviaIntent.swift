import AppIntents
import Foundation

/// Control Center and the Action button: open the app on a new chat.
public struct AskActoviaIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("ios:widget.ask.title", defaultValue: "Ask Actovia")
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.newChat(prompt: nil).url))
    }
}
