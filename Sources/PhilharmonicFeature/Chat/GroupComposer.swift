import ChatFeature
import SwiftUI

/// The group's composer: a message to the PM with pictures, Stop while the PM is at work, and — while the PM has
/// asked something — its question, its options and a reply.
struct GroupComposer: View {
    let model: GroupChatViewModel

    @State private var text = ""
    @State private var attachments = ComposerAttachments()
    @State private var preparing = 0
    @State private var sending = false
    /// The field is a UIKit text view (it takes a pasted picture), so its focus is plain state it keeps in step.
    @State private var isFocused = false
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.toneInk) private var toneInk
    @Environment(\.toneAccent) private var toneFill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = model.askUser {
                askUser(question)
                    .transition(.opacity)
            }
            if !attachments.isEmpty || preparing > 0 {
                ComposerPictureStrip(pictures: attachments.pictures, preparing: preparing) { attachments.remove($0) }
                    .transition(.opacity)
            }
            ComposerRowLayout(oneLineHeight: lineHeight) {
                ComposerToolsButton(tools: nil, attachments: attachments) { loaders in
                    Task { await add(loaders) }
                }
                .padding(.leading, ComposerRowLayout.inset - 16)
                // An answer to the PM is words only: a picture added then never went with it and was sent later
                // with the next message instead (ISSUE-249 M5).
                .disabled(model.askUser != nil)
                .composerRole(.leading)
                ComposerTextView(
                    text: $text, isFocused: $isFocused, placeholder: placeholder, tint: toneInk,
                    accessibilityIdentifier: "groupComposerField",
                    // A hardware keyboard's Return sends as the button does, and the field keeps the keyboard.
                    onReturnKey: { if state == .send && canSend { send(keepsFocus: true) } }
                ) { pictures in
                    // A pasted picture joins the message as a picked one does (ISSUE-299).
                    Task { await add(pictures.map { data in { data } }) }
                }
                .composerRole(.field)
                turnButton
                    .composerRole(.trailing)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, ComposerRowLayout.inset)
        .padding(.vertical, ComposerRowLayout.inset)
        .glassEffect(ComposerRowLayout.glass, in: .rect(cornerRadius: ComposerRowLayout.cornerRadius))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.askUser)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: attachments)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: text)
    }

    private func askUser(_ question: GroupQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: question.question)
                .font(.subheadline)
            if !question.options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(question.options, id: \.self) { option in
                        Button(option) { Task { await model.answer(option) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.trailing, 16 - ComposerRowLayout.inset)
    }

    private var placeholder: String {
        model.askUser != nil
            ? String(localized: "philharmonic:chat.groupChat.askUser.replyPlaceholder", defaultValue: "Reply to PM…")
            : String(localized: "philharmonic:chat.composer.placeholder", defaultValue: "Message your team…")
    }

    private var state: TurnButtonState { model.pmRunning && model.askUser == nil ? .stop : .send }

    private var canSend: Bool {
        GroupComposerRule.canSend(
            hasWords: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, hasPictures: !attachments.isEmpty,
            preparing: preparing, sending: sending, answering: model.askUser != nil)
    }

    private var turnButton: some View {
        let state = state
        return Button {
            switch self.state {
            case .stop: Task { await model.interrupt() }
            default: send()
            }
        } label: {
            TurnButtonLabel(
                state: state, glyph: TurnButtonLabel.glyph(state, scheme: colorScheme, accentGlyph: accentGlyph))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(TurnButtonLabel.fill(state, scheme: colorScheme, toneFill: toneFill, toneInk: toneInk))
        .disabled(state == .send && !canSend)
        .accessibilityIdentifier(state.identifier)
    }

    private func send(keepsFocus: Bool = false) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keepsFocus { isFocused = false }
        if model.askUser != nil {
            guard !words.isEmpty else { return }
            text = ""
            Task { await model.answer(words) }
            return
        }
        let pictures = attachments.pictures
        sending = true
        Task {
            // Cleared only once the message is in: a failed send keeps what was typed.
            if await model.send(text: words, pictures: pictures) {
                text = ""
                attachments.removeAll()
            }
            sending = false
        }
    }

    /// One at a time, as the chat's composer does: ten originals held at once would be hundreds of MB.
    private func add(_ loaders: [ComposerPicture.Loader]) async {
        preparing += loaders.count
        for load in loaders {
            defer { preparing -= 1 }
            guard !attachments.isFull, let data = await load(),
                let picture = try? await ComposerPicture.prepared(data)
            else { continue }
            attachments.append([picture])
        }
    }
}

/// Buttons in rows, wrapping to the width they have.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// When the composer's send button is live.
enum GroupComposerRule {
    /// Answering the PM, pictures do not count: the answer carries none (the picture button is off meanwhile), and
    /// any already added stay for the next message (ISSUE-249 M5).
    static func canSend(hasWords: Bool, hasPictures: Bool, preparing: Int, sending: Bool, answering: Bool) -> Bool {
        if sending { return false }
        if answering { return hasWords }
        return preparing == 0 && (hasWords || hasPictures)
    }
}
