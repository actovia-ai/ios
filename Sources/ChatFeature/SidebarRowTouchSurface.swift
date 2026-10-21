import SwiftUI
import UIKit

/// The touch side of a sidebar row: the tap that selects it and the finger-down state its tint follows, read in
/// UIKit, laid over the row.
///
/// Not SwiftUI gestures. The row used to read "a finger is down" from a `DragGesture(minimumDistance: 0)`, and a
/// zero-distance drag inside a `List` claims every touch that lands on it — `.simultaneousGesture` or not — so a
/// vertical swipe that started on a chat never reached the list's scroll view: the sidebar did not scroll at all
/// (measured in the simulator, on main as well). UIKit's own touch delivery is what a list cell is built for: the
/// scroll view delays a row's touches a moment, takes them back with `touchesCancelled` when the finger scrolls,
/// and a `UITapGestureRecognizer` fails as soon as the finger travels — which also leaves a left swipe to the
/// drawer instead of selecting the chat under it.
///
/// A long press shows the row's `menu`, if it has one, through a `UIContextMenuInteraction` of this view — and
/// only the menu: no lifted card, no snapshot of the row. SwiftUI's `.contextMenu` always lifts something (the
/// row's snapshot, or a `preview:` of its own), and the owner asked for the menu alone, attached at the row, as
/// ChatGPT's sidebar does. Here the lifted preview is this view, which is clear and has nothing in it, on a clear
/// platter with no shadow — so what comes up is the menu, anchored to the row it belongs to. The interaction's
/// recognizer and the tap share this view, so they are exclusive: a press that became the menu is never also a tap.
///
/// Hidden from VoiceOver: the row keeps its SwiftUI label, traits and actions (the menu's included, as named
/// actions on the row).
struct SidebarRowTouchSurface: UIViewRepresentable {
    let select: () -> Void
    let pressChanged: (Bool) -> Void
    /// The long-press menu, built when it opens (so it reflects the chat as it is then); nil for no menu.
    var menu: (() -> UIMenu)?

    func makeUIView(context: Context) -> RowTouchView {
        let view = RowTouchView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: RowTouchView, context: Context) {
        view.select = select
        view.pressChanged = pressChanged
        view.menu = menu
    }

    final class RowTouchView: UIView, UIContextMenuInteractionDelegate {
        var select: () -> Void = {}
        var pressChanged: (Bool) -> Void = { _ in }
        var menu: (() -> UIMenu)? {
            didSet {
                if menu != nil, menuInteraction == nil {
                    let interaction = UIContextMenuInteraction(delegate: self)
                    addInteraction(interaction)
                    menuInteraction = interaction
                } else if menu == nil, let menuInteraction {
                    removeInteraction(menuInteraction)
                    self.menuInteraction = nil
                }
            }
        }
        private var menuInteraction: UIContextMenuInteraction?
        static let longestTap: CFTimeInterval = 0.35

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(TimedTap(target: self, action: #selector(tapped)))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// A press held past `longestTap` was a long press — the row's menu — and its touch-up is not a tap: on a
        /// device a finger lifted as the menu came up selected the chat, which closed the drawer behind the menu.
        @objc private func tapped(_ recognizer: TimedTap) {
            guard recognizer.state == .ended, CACurrentMediaTime() - recognizer.touchDown <= Self.longestTap else { return }
            select()
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard let menu else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu() }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
            highlightPreviewForItemWithIdentifier identifier: any NSCopying
        ) -> UITargetedPreview? {
            invisiblePreview
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
            dismissalPreviewForItemWithIdentifier identifier: any NSCopying
        ) -> UITargetedPreview? {
            invisiblePreview
        }

        /// This view — clear, with nothing drawn in it — on a clear platter without a shadow, shaped as the row's
        /// pill so the menu lines up with the row.
        private var invisiblePreview: UITargetedPreview? {
            guard window != nil else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.shadowPath = UIBezierPath()
            parameters.visiblePath = UIBezierPath(
                roundedRect: bounds.insetBy(dx: 8, dy: 2), cornerRadius: 10)
            return UITargetedPreview(view: self, parameters: parameters)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            pressChanged(true)
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            pressChanged(false)
            super.touchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            pressChanged(false)
            super.touchesCancelled(touches, with: event)
        }
    }

    /// A tap that remembers when the finger came down. Read here, not in the view's `touchesBegan`: the list
    /// delays a row's own touches (a quick tap's `touchesBegan` arrives with its touch-up), but not its recognizers'.
    final class TimedTap: UITapGestureRecognizer {
        private(set) var touchDown: CFTimeInterval = 0

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            touchDown = CACurrentMediaTime()
            super.touchesBegan(touches, with: event)
        }
    }
}
