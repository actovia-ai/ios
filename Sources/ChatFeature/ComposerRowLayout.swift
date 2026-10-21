import SwiftUI

/// Which part of the composer's row a child is: the `+` on the left, the field, or one of the round buttons on the
/// right. Set with `.composerRole(_:)`; a child without one is laid out as a trailing button.
enum ComposerRole {
    case leading, field, trailing
}

private struct ComposerRoleKey: LayoutValueKey {
    static let defaultValue: ComposerRole = .trailing
}

extension View {
    func composerRole(_ role: ComposerRole) -> some View {
        layoutValue(key: ComposerRoleKey.self, value: role)
    }
}

/// Where the composer's row puts its parts, worked out once from their sizes so a test can check it without a view.
/// As ChatGPT's: while the text fits one line the field sits between `+` and the round buttons, a pill; once it
/// wraps the field takes the top on its own, full width, and the buttons a row under it, so nothing is ever centred
/// against a field of changing height.
///
/// The decision is made from the field's height *at the width it has beside the buttons*, whatever width it has
/// now: measured at its own width, text that wraps beside the buttons but fits alone on the wide line would flip
/// between the two layouts on every pass.
struct ComposerRowPlan: Equatable {
    var expanded: Bool
    var size: CGSize
    var leading: [CGRect]
    var field: CGRect
    var trailing: [CGRect]

    /// Past one and a half lines the text has wrapped (a line and a half, not two: a field's line is not exactly
    /// the font's, and a second line is well past the mark either way).
    static func expands(fieldHeight: CGFloat, oneLineHeight: CGFloat) -> Bool {
        fieldHeight > oneLineHeight * 1.5
    }

    /// - Parameters:
    ///   - width: the row's.
    ///   - leading: the `+` button's size (or none).
    ///   - trailing: the round buttons' sizes, left to right.
    ///   - fieldHeight: the field's height when proposed a width.
    ///   - spacing: between a button and the field, and between buttons.
    ///   - rowSpacing: between the field and the buttons' row once expanded.
    ///   - oneLineHeight: the height of one line of the field's text.
    static func make(
        width: CGFloat, leading: [CGSize], trailing: [CGSize], fieldHeight: (CGFloat) -> CGFloat,
        spacing: CGFloat, rowSpacing: CGFloat, oneLineHeight: CGFloat
    ) -> ComposerRowPlan {
        let buttons = leading + trailing
        let buttonsWidth = buttons.reduce(0) { $0 + $1.width }
        let buttonsHeight = buttons.map(\.height).max() ?? 0
        let compactWidth = max(0, width - buttonsWidth - spacing * CGFloat(buttons.count))
        let compactHeight = fieldHeight(compactWidth)
        let expanded = expands(fieldHeight: compactHeight, oneLineHeight: oneLineHeight)

        let fieldSize = expanded ? CGSize(width: width, height: fieldHeight(width)) : CGSize(width: compactWidth, height: compactHeight)
        let rowHeight = expanded ? buttonsHeight : max(buttonsHeight, fieldSize.height)
        let rowTop = expanded ? fieldSize.height + rowSpacing : 0
        let height = rowTop + rowHeight

        // Each button centred in the buttons' row; the field too while it shares the row.
        func centred(_ size: CGSize, x: CGFloat) -> CGRect {
            CGRect(x: x, y: rowTop + (rowHeight - size.height) / 2, width: size.width, height: size.height)
        }
        var x: CGFloat = 0
        var leadingFrames: [CGRect] = []
        for size in leading {
            leadingFrames.append(centred(size, x: x))
            x += size.width + spacing
        }
        let fieldFrame = expanded
            ? CGRect(origin: .zero, size: fieldSize)
            : centred(fieldSize, x: x)
        var right = width
        var trailingFrames: [CGRect] = []
        for size in trailing.reversed() {
            right -= size.width
            trailingFrames.append(centred(size, x: right))
            right -= spacing
        }
        return ComposerRowPlan(
            expanded: expanded, size: CGSize(width: width, height: height), leading: leadingFrames,
            field: fieldFrame, trailing: trailingFrames.reversed())
    }
}

/// The composer's row laid out by `ComposerRowPlan`: one `Layout` with the same children in both shapes, so the
/// field keeps its identity (its focus, the keyboard) across the change and the move animates.
struct ComposerRowLayout: Layout {
    /// The round buttons at either end, `+` and the turn button, one size.
    static let buttonSide: CGFloat = 36
    /// The pill's padding around them, the same on every side: the buttons sit concentric in the pill's ends, never
    /// closer to the side than to the top (owner, 2026-10-08: a 64 pt bar read tall, its buttons crowding the sides).
    static let inset: CGFloat = 8
    /// The pill's corners: half its one-line height (a button and the inset above and below), so one line reads as a
    /// capsule, as the desktop's; more lines, a quote or pictures and it is a rounded box.
    static let cornerRadius: CGFloat = (buttonSide + 2 * inset) / 2
    /// The composer's glass: a light wash of the page colour under it, so a draft grown to several lines over a busy
    /// transcript is not read through the text behind it.
    static var glass: Glass { .regular.tint(Color(.systemBackground).opacity(0.5)) }

    /// The height of one line of the field's text, at the reader's text size.
    var oneLineHeight: CGFloat
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = plan(width: bounds.width, subviews: subviews)
        var leading = plan.leading.makeIterator()
        var trailing = plan.trailing.makeIterator()
        for subview in subviews {
            let frame: CGRect?
            switch subview[ComposerRoleKey.self] {
            case .leading: frame = leading.next()
            case .field: frame = plan.field
            case .trailing: frame = trailing.next()
            }
            guard let frame else { continue }
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func plan(width: CGFloat, subviews: Subviews) -> ComposerRowPlan {
        let field = subviews.first { $0[ComposerRoleKey.self] == .field }
        return ComposerRowPlan.make(
            width: width,
            leading: subviews.filter { $0[ComposerRoleKey.self] == .leading }.map { $0.sizeThatFits(.unspecified) },
            trailing: subviews.filter { $0[ComposerRoleKey.self] == .trailing }.map { $0.sizeThatFits(.unspecified) },
            fieldHeight: { width in field?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0 },
            spacing: spacing, rowSpacing: rowSpacing, oneLineHeight: oneLineHeight)
    }
}
