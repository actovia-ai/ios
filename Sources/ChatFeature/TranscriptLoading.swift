import SwiftUI

/// What a chat shows while its first page loads (desktop spec 2026-10-01 §D): the shape of a conversation — a question
/// on the right, an answer's lines on the left — so the screen has its layout before its words. Only once the load has
/// been slow for 300 ms: on the LAN the page arrives first and nothing flashes; over a tunnel the screen is not blank.
public struct TranscriptSkeleton: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer(minLength: 80)
                        RoundedRectangle(cornerRadius: 18).frame(width: 180, height: 40)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach([1.0, 0.92, 0.8, 0.6], id: \.self) { width in
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 6).frame(width: proxy.size.width * width)
                            }
                            .frame(height: 14)
                        }
                    }
                }
            }
            Spacer()
        }
        .foregroundStyle(.quaternary)
        .padding(.horizontal)
        .padding(.top, 8)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shown)
        .accessibilityElement()
        .accessibilityLabel(
            String(
                localized: "chat:history.loading", defaultValue: "Loading the conversation",
                comment: "VoiceOver label of the placeholder shown while a conversation loads."))
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            shown = true
        }
    }
}

/// The top of a transcript with older runs to load: a spinner while a page loads — once it has taken 300 ms — and
/// otherwise nothing. Its appearing is what asks for the page.
struct OlderHistoryRow: View {
    let isLoading: Bool
    @State private var slow = false

    var body: some View {
        HStack {
            Spacer()
            if isLoading && slow {
                ProgressView()
                    .accessibilityLabel(
                        String(
                            localized: "chat:history.loadingOlder", defaultValue: "Loading earlier messages",
                            comment: "VoiceOver label of the spinner shown while older messages load."))
            }
            Spacer()
        }
        .frame(minHeight: 1)
        .task(id: isLoading) {
            slow = false
            guard isLoading else { return }
            try? await Task.sleep(for: .milliseconds(300))
            slow = true
        }
    }
}
