import NetworkingKit
import OdyKit
import SwiftUI

/// What an unpaired device opens on: what this app is, and the way to pair — the same scan and paste as Settings →
/// Computer, so there is one pairing flow. Without it the app opened on a chat that could only fail.
public struct PairingWelcomeView: View {
    let connection: ServerConnection
    let onPaired: () -> Void

    public init(connection: ServerConnection, onPaired: @escaping () -> Void) {
        self.connection = connection
        self.onPaired = onPaired
    }

    /// Where the desktop app is downloaded from (the desktop's `package.json` `homepage`).
    static let website = URL(string: "https://actovia.yancey.app")!  // l10n:ignore: a URL

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        // Ody, not yet anywhere: the offline scene, as Health's onboarding shows its own.
                        OdySceneView(.offline)
                            .frame(width: 132, height: 132)
                            .clipShape(.rect(cornerRadius: 30, style: .continuous))
                            .padding(.bottom, 6)
                        Text("ios:onboarding.title")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("ios:onboarding.message")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                PairingSection(connection: connection, style: .welcome) {
                    if connection.isPaired { onPaired() }
                }

                Section {
                    Link(destination: Self.website) {
                        Label("ios:onboarding.getActovia", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("ios:onboarding.noActoviaYet")
                }
            }
        }
    }
}
