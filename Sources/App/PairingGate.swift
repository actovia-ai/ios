import NetworkingKit
import SettingsFeature
import SwiftUI

/// An unpaired device has no computer to talk to, so it opens on `PairingWelcomeView` instead of a chat whose every
/// request fails; pairing lets it through, and unpairing (here, or a revocation from the computer) brings it back.
/// The Simulator reaches the computer's loopback listener without pairing and goes straight through. Switching to
/// another paired computer starts the content again (`computer`), so no screen keeps the last computer's data.
struct PairingGate<Content: View>: View {
    let connection: ServerConnection
    @ViewBuilder let content: () -> Content

    @State private var needsPairing: Bool
    /// Bumped whenever the computer requests go to changes; the content's identity.
    @State private var computer = 0

    init(connection: ServerConnection, @ViewBuilder content: @escaping () -> Content) {
        self.connection = connection
        self.content = content
        _needsPairing = State(initialValue: Self.requiresPairing && !connection.isPaired)
    }

    var body: some View {
        Group {
            if needsPairing {
                PairingWelcomeView(connection: connection) { needsPairing = false }
                    .transition(.opacity)
            } else {
                content().id(computer)
            }
        }
        .animation(.easeOut(duration: 0.25), value: needsPairing)
        .task {
            // One registration for the app's life: the gate is the root and is never rebuilt.
            connection.onComputerChange { [connection] in
                Task { @MainActor in
                    if Self.requiresPairing && !connection.isPaired {
                        needsPairing = true
                    } else {
                        computer += 1
                    }
                }
            }
        }
    }

    /// A device must pair; the Simulator uses the manual address (Settings → Computer). `-PairingWelcome` shows the
    /// welcome there too, for screenshots.
    static var requiresPairing: Bool {
        #if targetEnvironment(simulator)
            ProcessInfo.processInfo.arguments.contains("-PairingWelcome")
        #else
            true
        #endif
    }
}
