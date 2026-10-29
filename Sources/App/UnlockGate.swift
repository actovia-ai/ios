import NetworkingKit
import Models
import SwiftUI
import UIKit

/// Holds the app behind Face ID while the pairing credential is locked: on a
/// cold start, and after more than `ServerConnection.backgroundGrace` in the
/// background. The token lives in the Keychain behind biometrics and is only
/// ever held in memory between those moments. An unpaired app (the Simulator)
/// has nothing to unlock and goes straight through.
///
/// Locking again covers the app; it does not take it down (ISSUE-298). The content used to be swapped out for the
/// lock screen, which destroyed the shell and everything it held — the chat on screen, the workspace, the group — so
/// every Face ID after a while in the background landed on a new chat. Now the content, once it has been shown, stays
/// mounted and is where it was when the cover lifts.
///
/// The cover is a window of its own above everything (`LockCoverWindow`), not a view over the content: a sheet, a
/// full-screen cover or an alert the content presented is drawn in its own presentation layer and stood above an
/// in-tree cover, visible and tappable. The window covers them all, takes key (so the keyboard goes), and is modal to
/// VoiceOver; the content is hidden from VoiceOver and touches as well while it is up.
struct UnlockGate<Content: View>: View {
    let connection: ServerConnection
    @ViewBuilder let content: () -> Content

    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: UnlockPresentation
    @State private var isUnlocking = false
    @State private var backgroundedAt: Date?
    @State private var cover = LockCoverWindow()

    init(connection: ServerConnection, @ViewBuilder content: @escaping () -> Content) {
        self.connection = connection
        self.content = content
        _presentation = State(
            initialValue: UnlockPresentation(
                isLocked: !UnlockGateDemo.isEnabled && connection.isPaired && !connection.isUnlocked))
    }

    private var isLocked: Bool { presentation.isLocked }
    private var isPaired: Bool { UnlockGateDemo.isEnabled || connection.isPaired }

    var body: some View {
        ZStack {
            if presentation.mountsContent {
                content()
                    .allowsHitTesting(!presentation.coversContent)
                    .accessibilityHidden(presentation.coversContent)
            }
            // In the tree as well: on a cold start there is no content under it, and should the cover window not
            // come up (no scene yet) the page is still covered.
            if presentation.coversContent {
                lockedView
                    .background(Color(.systemBackground).ignoresSafeArea())
            }
        }
        .task { await unlockIfNeeded() }
        .onChange(of: presentation.needsCoverWindow, initial: true) { syncCover() }
        .onChange(of: isUnlocking) { syncCover() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let since = backgroundedAt,
                   Date().timeIntervalSince(since) > UnlockGateDemo.grace,
                   isPaired
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

    /// Shows, refreshes or takes down the cover window to match the gate. Only over mounted content: before the first
    /// unlock there is nothing under the in-tree lock screen to cover.
    private func syncCover() {
        if presentation.needsCoverWindow {
            cover.show(AnyView(lockedView.background(Color(.systemBackground).ignoresSafeArea())))
        } else {
            cover.hide()
        }
    }

    private func unlockIfNeeded() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        #if DEBUG
            if UnlockGateDemo.isEnabled {
                try? await Task.sleep(for: .seconds(3))
                presentation.settle(stillLocked: false)
                return
            }
        #endif
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

/// The lock screen as a window over the whole scene, presentations included (see `UnlockGate`).
@MainActor
final class LockCoverWindow {
    private var window: UIWindow?
    private var host: UIHostingController<AnyView>?
    /// The window that was key before the cover took it, given back when the cover goes.
    private weak var previousKey: UIWindow?

    func show(_ content: AnyView) {
        if let host {
            host.rootView = content
            return
        }
        guard let scene = Self.scene else { return }
        // A field still editing under the cover would keep its keyboard above the content.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        previousKey = scene.keyWindow
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .systemBackground
        // VoiceOver reads the cover alone, not the sheets and pages under it.
        host.view.accessibilityViewIsModal = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        self.host = host
    }

    func hide() {
        guard let window else { return }
        window.isHidden = true
        self.window = nil
        host = nil
        previousKey?.makeKey()
    }

    var isShowing: Bool { window != nil }

    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// DEBUG: `-UnlockGateDemo` makes the Simulator (which is never paired) behave as a paired device — locked after a
/// second in the background, unlocked three seconds after it comes back, no Face ID — to see what the cover
/// covers. Release builds always use the real grace and the real unlock.
enum UnlockGateDemo {
    static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-UnlockGateDemo")
        #else
            false
        #endif
    }

    static var grace: TimeInterval { isEnabled ? 1 : ServerConnection.backgroundGrace }
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
    /// The cover window is up: locked over content that is mounted, and so may have a sheet, an alert or a keyboard
    /// above it that an in-tree cover would not reach.
    var needsCoverWindow: Bool { isLocked && hasShownContent }

    mutating func lock() { isLocked = true }

    /// After an unlock attempt: still locked (cancelled, failed) or open.
    mutating func settle(stillLocked: Bool) {
        isLocked = stillLocked
        if !stillLocked { hasShownContent = true }
    }
}
