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
/// Hidden from VoiceOver: the row keeps its SwiftUI label, traits and actions.
struct SidebarRowTouchSurface: UIViewRepresentable {
    let select: () -> Void
    let pressChanged: (Bool) -> Void

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
    }

    final class RowTouchView: UIView {
        var select: () -> Void = {}
        var pressChanged: (Bool) -> Void = { _ in }
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
