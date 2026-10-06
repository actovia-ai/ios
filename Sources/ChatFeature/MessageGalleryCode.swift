#if DEBUG
    import Foundation

    /// The gallery's run for code in an answer: three fenced blocks — TypeScript, Swift and a shell session — so
    /// the language strip (`TSX`, `Swift`, `Console`) and the Xcode colours can be looked at in both schemes.
    /// `-MessageGallerySection code` scrolls to it.
    extension MessageGalleryFixtures {
        static let codeRuns: [Run] = [
            Run(
                title: "Code in the answer: TSX, Swift, a shell session",
                json: codeRun())
        ]

        private static func codeRun() -> String {
            let tsx = """
            import { useState } from 'react'

            // A counter, the smallest possible.
            export function Counter({ start = 0 }: { start?: number }) {
              const [count, setCount] = useState(start)
              return <button onClick={() => setCount((n) => n + 1)}>{count}</button>
            }
            """
            let swift = """
            import SwiftUI

            /// The same counter, for the phone.
            struct Counter: View {
                @State private var count = 0
                var body: some View {
                    Button(action: { count += 1 }) { Text(verbatim: String(count)) }
                        .buttonStyle(.borderedProminent)
                }
            }
            """
            let shell = """
            $ swift --version
            Apple Swift version 6.3.2 (swift-6.3.2-RELEASE)
            $ xcodebuild -list | head -3
            """
            let reply = "Here is the counter both ways, and what the machine says:\n\n```tsx\n\(tsx)\n```\n\n```swift\n\(swift)\n```\n\n```console\n\(shell)\n```"
            let messages: [[String: Any]] = [
                ["id": "code1", "runId": "code1", "role": "user", "content": "Show me a counter in React and in SwiftUI.", "timestamp": 1000],
                [
                    "id": "code1a", "runId": "code1", "role": "assistant", "content": [["type": "text", "text": reply]],
                    "stopReason": "stop", "durationMs": 3200, "timestamp": 4200,
                ],
            ]
            let data = try! JSONSerialization.data(withJSONObject: messages, options: [.withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
    }
#endif
