import ChatFeature
import MarkdownKit
import Models
import NetworkingKit
import SettingsFeature
import SwiftUI
import WidgetKitShared

@main
struct ActoviaApp: App {
    var body: some Scene {
        WindowGroup(id: "main") { ActoviaWindow() }
    }
}

/// Every scene owns its connection and streams; opening another window never retargets a live reply.
private struct ActoviaWindow: View {
    @State private var services = WindowServices()
    @State private var toneModel = ColorToneModel()
    @State private var pendingLink = PendingLink()
    @Environment(\.scenePhase) private var scenePhase

    private var connection: ServerConnection { services.connection }
    private var serverConfig: ServerConfigStore { services.serverConfig }
    private var apiClient: APIClient { services.apiClient }
    private var streamManager: ChatStreamManager { services.streamManager }
    private var reporter: LogReporter { services.reporter }
    private var widgetWriter: WidgetSnapshotWriter { services.widgetWriter }

    var body: some View {
            Group {
                #if DEBUG
                // The galleries of chat content are painted as a chat is.
                if MarkdownGalleryLaunch.isEnabled {
                    MarkdownGalleryView().chatTone(toneModel)
                } else if MessageGalleryLaunch.isEnabled {
                    MessageGalleryView().chatTone(toneModel)
                } else if SettingsGalleryLaunch.isEnabled {
                    SettingsGalleryView()
                } else if OdyGalleryLaunch.isEnabled {
                    OdyGalleryView()
                } else if HealthGalleryLaunch.isEnabled {
                    HealthGalleryView()
                } else if WidgetGalleryLaunch.isEnabled {
                    WidgetGalleryView()
                } else if CardPrototypesLaunch.isEnabled {
                    CardPrototypesView(embedded: false).chatTone(toneModel)
                } else {
                    shell
                }
                #else
                shell
                #endif
            }
            // The tone is the chat's: `ChatDetailView` paints itself in it. Everything around a chat — the
            // drawer, Settings — keeps the system's own look, so the tone reads as the conversation's colour
            // and not as the app's.
            .environment(\.accentGlyph, toneModel.tone.glyphColor)
            .environment(\.colorTone, toneModel.tone)
            .environment(\.toneAccent, toneModel.tone.color)
            .environment(\.toneInk, toneModel.tone.inkColor)
            .environment(toneModel)
            .environment(\.renderDiagnostics, Self.diagnostics(reporter))
            // The scene's one current activity: the frontmost `screenTitle` names a screenshot.
            .publishesScreenTitle()
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reporter.flushSoon() }
            }
            .onOpenURL { pendingLink.offer($0) }
        }
    private static func diagnostics(_ reporter: LogReporter) -> RenderDiagnostics {
        RenderDiagnostics { scope, message, attributes in
            reporter.report(
                .warn, scope: scope, message: message, attributes: attributes.mapValues { .string($0) })
        }
    }

    private var shell: some View {
        PairingGate(connection: connection) {
            UnlockGate(connection: connection) {
                AppShell(
                    apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig,
                    widgetWriter: widgetWriter, pendingLink: pendingLink)
            }
        }
        .launchSplash()
    }
}

@MainActor
final class WindowServices {
    let connection: ServerConnection
    let serverConfig: ServerConfigStore
    let apiClient: APIClient
    let streamManager: ChatStreamManager
    let reporter: LogReporter
    let widgetWriter: WidgetSnapshotWriter
    init(store: any CredentialStoring = KeychainCredentialStore()) {
        // One connection, and one URLSession — its own, which trusts only the
        // certificate this device was paired with — shared by everything that
        // talks to the computer. Unpaired (the Simulator), both are inert and
        // requests go to the plain manual address.
        let connection = ServerConnection(store: store)
        connection.onComputerChange { Task { @MainActor in ChatCaches.clearAll() } }
        let status = ConnectionStatus()
        OfflineCacheLifecycle.install(on: connection, status: status)
        // Nothing of the old computer stays on the Home Screen.
        let widgetWriter = WidgetSnapshotWriter()
        connection.onComputerChange { Task { @MainActor in widgetWriter.computerChanged() } }
        self.widgetWriter = widgetWriter
        let config = ServerConfigStore()
        config.connection = connection
        self.connection = connection
        serverConfig = config
        // Reports wait while Face ID still holds the token (the UnlockGate's own condition), then go to the computer.
        let reporter = LogReporter(
            session: connection.session, serverConfig: config,
            isReady: { [connection] in !connection.isPaired || connection.isUnlocked })
        self.reporter = reporter
        apiClient = APIClient(
            session: connection.session, serverConfig: config, reporter: reporter, status: status)
        streamManager = ChatStreamManager(
            sseClient: SSEClient(session: connection.session, reporter: reporter))
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-EmitTestLogReport") {
                reporter.report(
                    .warn, scope: "debug", message: "Test report from the -EmitTestLogReport launch argument")
            }
            SettingsDebugHooks.cardPrototypes = { AnyView(CardPrototypesView()) }
        #endif
    }

}

#if DEBUG
extension View {
    /// A gallery of chat content, painted as a chat is (`ChatDetailView`): the tone's ink as the tint, and links
    /// underlined where that ink is the text's own colour.
    fileprivate func chatTone(_ model: ColorToneModel) -> some View {
        colorTone(model.tone).environment(\.markdownUnderlinesLinks, model.tone == .neutral)
    }
}
#endif
