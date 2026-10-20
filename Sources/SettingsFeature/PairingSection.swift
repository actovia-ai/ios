import AVFoundation
import NetworkingKit
import SwiftUI
import UIKit

/// Settings → Computer. A device reaches Actovia only after it has been paired:
/// the computer shows a QR code (Settings → Devices → Pair a device) carrying a
/// one-time code and the fingerprint of the certificate to trust. A device can be
/// paired with several computers (a home Mac mini with the release, a laptop with a
/// development build): each is a row, a tap makes it the current one, a swipe unpairs it.
struct PairingSection: View {
    @State private var viewModel: PairingViewModel
    @State private var isScanning = false
    /// A link the scanner found; acted on once its screen has been popped, so
    /// the result alert isn't presented into a transition and lost.
    @State private var scannedLink: String?
    @State private var cameraDenied = false
    /// The computer whose Unpair is being confirmed.
    @State private var confirmUnpair: PairedComputer?
    /// Paired already, and showing the steps to pair one more.
    @State private var addingComputer = false
    private let onChange: () -> Void

    /// `onChange` fires after pairing or unpairing — the server the rest of
    /// Settings talks to has just changed.
    init(connection: ServerConnection, onChange: @escaping () -> Void) {
        _viewModel = State(
            initialValue: PairingViewModel(connection: connection, deviceName: UIDevice.current.name))
        self.onChange = onChange
    }

    var body: some View {
        Section {
            ForEach(viewModel.computers) { computer in
                computerRow(computer)
            }
            if viewModel.isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("ios:settings.pairing.inProgress")
                }
            } else if !viewModel.isPaired || addingComputer {
                Text(
                    "ios:settings.pairing.instructions"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if QRScannerView.isSupported {
                    Button("ios:settings.pairing.scanCode") { Task { await openScanner() } }
                        .navigationDestination(isPresented: $isScanning) {
                            ScannerScreen { link in
                                scannedLink = link
                                isScanning = false
                            }
                        }
                }
                Button("ios:settings.pairing.pasteLink") {
                    pair(from: UIPasteboard.general.string)
                }
            } else {
                Button("ios:settings.pairing.pairAnother") { addingComputer = true }
            }
        } header: {
            Text("ios:settings.pairing.sectionTitle")
        } footer: {
            if viewModel.computers.count > 1 {
                Text("ios:settings.pairing.computersFooter")
            }
        }
        .onChange(of: isScanning) { _, showing in
            if !showing { pairWithScannedLink() }
        }
        .alert(
            unpairTitle,
            isPresented: Binding(get: { confirmUnpair != nil }, set: { if !$0 { confirmUnpair = nil } }),
            presenting: confirmUnpair
        ) { computer in
            Button("ios:settings.pairing.unpair", role: .destructive) {
                viewModel.forget(computer.fingerprint)
                onChange()
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: { _ in
            Text("ios:settings.pairing.unpairConfirmMessage")
        }
        .alert("ios:settings.pairing.cameraDeniedTitle", isPresented: $cameraDenied) {
            Button("ios:settings.pairing.openSystemSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text("ios:settings.pairing.cameraDeniedMessage")
        }
        .alert(
            "ios:settings.pairing.failedTitle",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } })
        ) {
            Button("ios:app.alert.ok", role: .cancel) {}
        } message: {
            // The reason, then the technical detail beneath it — what to report.
            Text(verbatim: [viewModel.errorMessage, viewModel.errorDetail].compactMap { $0 }.joined(separator: "\n\n"))
        }
    }

    /// A paired computer: its name and the address tried first, a check on the current one. A tap switches to it,
    /// a swipe unpairs it.
    private func computerRow(_ computer: PairedComputer) -> some View {
        Button {
            Task { if await viewModel.switchTo(computer.fingerprint) { onChange() } }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: computer.name)
                        .foregroundStyle(.primary)
                    if let host = computer.host {
                        Text(verbatim: host)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if computer.isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("ios:settings.pairing.current"))
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(viewModel.isWorking)
        .accessibilityAddTraits(computer.isActive ? .isSelected : [])
        .swipeActions {
            Button("ios:settings.pairing.unpair", role: .destructive) { confirmUnpair = computer }
        }
        .contextMenu {
            Button("ios:settings.pairing.unpair", role: .destructive) { confirmUnpair = computer }
        }
    }

    private var unpairTitle: String {
        guard let name = confirmUnpair?.name else { return "" }
        return String(
            localized: "ios:settings.pairing.unpairNamedTitle", defaultValue: "Unpair from \(name)?",
            comment: "Settings → Computer, confirming Unpair. %@ is the computer's name.")
    }

    /// The system prompt comes up here, before the scanner screen, not over it.
    private func openScanner() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            cameraDenied = true
            return
        }
        isScanning = true
    }

    private func pairWithScannedLink() {
        guard let link = scannedLink else { return }
        scannedLink = nil
        pair(from: link)
    }

    private func pair(from text: String?) {
        Task {
            if await viewModel.pair(from: text) {
                addingComputer = false
                onChange()
            }
        }
    }
}
