import NetworkingKit
import SwiftUI

/// Settings → Computer: pairing, and the manual address the Simulator uses.
struct ConnectionSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel
    let connection: ServerConnection?
    @Binding var pairingRevision: Int

    /// Reads `pairingRevision` so that pairing or unpairing re-evaluates it. The Simulator's only: a device reaches
    /// the computer by pairing — the QR code carries its addresses and port — and a typed address could only fail.
    private var showsManualAddress: Bool {
        #if targetEnvironment(simulator)
            pairingRevision >= 0 && connection?.isPaired != true
        #else
            false
        #endif
    }

    var body: some View {
        Form {
            if let connection {
                PairingSection(connection: connection) {
                    // A different server from here on: reload what it holds.
                    pairingRevision += 1
                    Task { await viewModel.loadSettings() }
                }
            }

            // The manual address reaches the computer's plain loopback
            // listener — the Simulator's way in. A paired device ignores it.
            if showsManualAddress {
                Section("ios:settings.connection.sectionTitle") {
                    TextField(
                        text: $viewModel.serverURLText,
                        prompt: Text(verbatim: "http://localhost:60223")
                    ) {
                        Text("ios:settings.connection.serverAddress")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit {
                        // A new address means a different server: reload its provider settings.
                        if viewModel.saveServerURL() {
                            Task { await viewModel.loadSettings() }
                        }
                    }
                }
            }

            SettingsErrorSection(message: viewModel.errorMessage)
        }
    }
}

struct SettingsErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Text(message).foregroundStyle(.red)
            }
        }
    }
}
