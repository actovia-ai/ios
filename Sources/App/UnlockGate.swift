import NetworkingKit
import Models
import SwiftUI

/// Holds the app behind Face ID while the pairing credential is locked: on a
/// cold start, and after more than `ServerConnection.backgroundGrace` in the
/// background. The token lives in the Keychain behind biometrics and is only
/// ever held in memory between those moments. An unpaired app (the Simulator)
/// has nothing to unlock and goes straight through.
///
/// Locking again covers the app; it does not take it down (ISSUE-298). The content used to be swapped out for the
/// lock screen, which destroyed the shell and everything it held — the chat on screen, the workspace, the group — so
/// every Face ID after a while in the background landed on a new chat. Now the content, once it has been shown, stays
/// mounted under an opaque cover, hidden from touches and VoiceOver, and is where it was when the cover lifts.
struct UnlockGate<Content: View>: View {
    let connection: ServerConnection
    @ViewBuilder let content: () -> Content

    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: UnlockPresentation
    @State private var isUnlocking = false
    @State private var backgroundedAt: Date?

    init(connection: ServerConnection, @ViewBuilder content: @escaping () -> Content) {
        self.connection = connection
        self.content = content
        _presentation = State(initialValue: UnlockPresentation(isLocked: connection.isPaired && !connection.isUnlocked))
    }

    private var isLocked: Bool { presentation.isLocked }

    var body: some View {
        ZStack {
            if presentation.mountsContent {
                content()
                    .allowsHitTesting(!presentation.coversContent)
                    .accessibilityHidden(presentation.coversContent)
            }
            if presentation.coversContent {
                lockedView
                    .background(Color(.systemBackground).ignoresSafeArea())
            }
        }
        .task { await unlockIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let since = backgroundedAt,
                   Date().timeIntervalSince(since) > ServerConnection.backgroundGrace,
                   connection.isPaired
                {
                    connection.lock()
                    presentation.lock()
                }
                backgroundedAt = nil
                Task { await unlockIfNeeded() }
            default:
                break
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("ios:app.lock.title")
                .font(.headline)
            Button("ios:app.lock.unlockButton") { Task { await unlockIfNeeded() } }
                .buttonStyle(.borderedProminent)
                .disabled(isUnlocking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenTitle(
            String(
                localized: "ios:app.lock.title", defaultValue: "Actovia is locked",
                comment: "Shown full-screen while the pairing credential is locked behind Face ID. Actovia is the app's name."))
    }

    private func unlockIfNeeded() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        do {
            try await connection.unlock(
                reason: String(
                    localized: "ios:app.lock.biometricReason", defaultValue: "Unlock the connection to your computer",
                    comment: "The reason shown in the Face ID / passcode prompt."))
            // Unpaired meanwhile (revoked, then cleared): nothing left to guard.
            presentation.settle(stillLocked: connection.isPaired && !connection.isUnlocked)
        } catch {
            // Cancelled or failed: stay locked; the button tries again.
        }
    }
}

/// What the gate shows: whether the app is mounted at all and whether the lock covers it. The app is not built before
/// the first unlock (nothing could load), and once built it is never taken down by a lock again, only covered.
struct UnlockPresentation: Equatable {
    private(set) var isLocked: Bool
    /// The app has been on screen this launch, so a later lock keeps it.
    private(set) var hasShownContent: Bool

    init(isLocked: Bool) {
        self.isLocked = isLocked
        hasShownContent = !isLocked
    }

    var mountsContent: Bool { hasShownContent }
    var coversContent: Bool { isLocked }

    mutating func lock() { isLocked = true }

    /// After an unlock attempt: still locked (cancelled, failed) or open.
    mutating func settle(stillLocked: Bool) {
        isLocked = stillLocked
        if !stillLocked { hasShownContent = true }
    }
}
