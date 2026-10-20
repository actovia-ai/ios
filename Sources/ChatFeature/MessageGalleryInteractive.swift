#if DEBUG
import Foundation

/// The gallery's runs for the interactive blocks: a questionnaire waiting for its answer, a confirmation waiting for
/// its, and a questionnaire answered — frozen with its picks, the answer under it as a card, and the reply after it.
/// `-MessageGallerySection ask|confirm|answered|steps|entity|stock` scrolls to one; `steps` has a search behind it whose
/// thumbnails the steps use, `entity` two entity links, `stock` a chart.
extension MessageGalleryFixtures {
    static let askSource =
        #"{"title":"A few details first","questions":[{"id":"where","text":"Where does it itch most?","type":"single","options":["Lower legs","Arms","All over"],"other":true},{"id":"when","text":"When is it worst?","type":"multi","options":["After a shower","At night","All day"]}],"note":"Anything else I should know?","submit":"Send"}"#
    static let confirmSource =
        #"{"title":"Add this trip to your calendar?","details":"**Oct 21–25**, five days, 17 stops; calendar *Travel*.","approve":"Add it","reject":"Not now","note":"Anything to change?"}"#
    static let stepsSource =
        #"{"title":"Restringing an acoustic guitar","steps":[{"text":"Loosen the old string at the tuning peg and pull the bridge pin.","image":"https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Acoustic_guitar_bridge_pins.jpg/320px-Acoustic_guitar_bridge_pins.jpg"},{"text":"Seat the new string's ball end under the pin, then thread the other end through the peg."},{"text":"Wind two or three turns, tuning up slowly and stretching the string as you go.","image":"https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Guitar_headstock_tuning.jpg/320px-Guitar_headstock_tuning.jpg"},{"text":"Trim the excess and tune once more.","image":"https://cdn.example.com/original/trim.jpg"}]}"#
    static let stockSource =
        #"{"symbol":"NASDAQ:AAPL","note":"Flat on the day after yesterday's 3% rise; the earnings call is tomorrow."}"#

    static let interactiveRuns: [Run] = [
        Run(
            title: "A questionnaire in the answer",
            json: interactiveRun(
                id: "ib1", question: "My legs itch after every shower. What can I do?",
                reply: "That's common when the air is dry. A few details first, so I can be specific:\n\n```actovia-ask\n\(askSource)\n```")),
        Run(
            title: "A confirmation before an action",
            json: interactiveRun(
                id: "ib2", question: "Put the Kyoto trip in my calendar.",
                reply: "Here's what I'd add:\n\n```actovia-confirm\n\(confirmSource)\n```")),
        Run(title: "Answered: the block frozen, the answer as a card", json: answeredRun()),
        Run(title: "Illustrated steps, pictured from the run's own search", json: stepsRun()),
        Run(
            title: "Entity links: a name opens its Wikipedia summary",
            json: interactiveRun(
                id: "ib5", question: "Who was Marie Curie, and where did she work?",
                reply:
                    "[Marie Curie](entity:Marie_Curie) was a Polish-born physicist and chemist who did most of her work in Paris, at the [Sorbonne](entity:University_of_Paris), where she became the first woman to hold a professorship. She won two Nobel Prizes — physics in 1903 and chemistry in 1911.")),
        Run(
            title: "A stock chart with the model's reading",
            json: interactiveRun(
                id: "ib6", question: "How's Apple doing today?",
                reply: "Quiet so far:\n\n```actovia-stock\n\(stockSource)\n```")),
    ]

    /// The interactive runs' names, in their order at the end of `runs`.
    static let interactiveNames = ["ask", "confirm", "answered", "steps", "entity", "stock"]

    /// The run index a `-MessageGallerySection` name stands for.
    static func namedSection(_ name: String) -> Int? {
        // The code run sits just before the interactive ones (MessageGallery.swift keeps that order).
        if name == "code" { return runs.count - interactiveRuns.count - codeRuns.count }
        guard let offset = interactiveNames.firstIndex(of: name) else { return nil }
        return runs.count - interactiveRuns.count + offset
    }

    private static func interactiveRun(
        id: String, question: String, reply: String, then rest: [[String: Any]] = []
    ) -> String {
        let messages: [[String: Any]] =
            [
                ["id": id, "runId": id, "role": "user", "content": question, "timestamp": 1000],
                [
                    "id": "\(id)a", "runId": id, "role": "assistant", "content": [["type": "text", "text": reply]],
                    "stopReason": "stop", "timestamp": 1200,
                ],
            ] + rest
        let data = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func answeredRun() -> String {
        guard case .ask(let ask)? = InteractiveBlock.parse(.ask, source: askSource) else { return "[]" }
        let answer = InteractiveAnswer.composeAsk(
            ask, ref: "ib3",
            responses: ["where": .init(options: ["Lower legs"]), "when": .init(options: ["After a shower", "At night"])],
            note: "I use an unscented lotion.", labels: .current)
        let rest: [[String: Any]] = [
            ["id": "ib4", "runId": "ib4", "role": "user", "content": answer, "timestamp": 1400],
            [
                "id": "ib4a", "runId": "ib4", "role": "assistant",
                "content": [
                    [
                        "type": "text",
                        "text":
                            "Then it's most likely dry skin from hot showers. Keep them short and lukewarm, and put the lotion on within three minutes, while your skin is still damp.",
                    ]
                ],
                "stopReason": "stop", "timestamp": 1600,
            ],
        ]
        return interactiveRun(
            id: "ib3", question: "My legs itch after every shower. What can I do?",
            reply: "A few details first, so I can be specific:\n\n```actovia-ask\n\(askSource)\n```", then: rest)
    }

    /// A search whose results carry the thumbnails the steps use — a page's thumbnail and an image result's — and an
    /// original the last step names, which is dropped: the step is drawn without a picture.
    private static func stepsRun() -> String {
        let details = #"""
            [{"rank":1,"link":"https://guitars.example/restringing","title":"How to restring an acoustic guitar","snippet":"","hostname":"guitars.example","siteName":"Guitar Notes",
              "thumbnail":"https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Acoustic_guitar_bridge_pins.jpg/320px-Acoustic_guitar_bridge_pins.jpg",
              "media":[{"kind":"image","title":"Tuning up","url":"https://cdn.example.com/original/tuning.jpg","sourceUrl":"https://guitars.example/restringing","thumbnailUrl":"https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Guitar_headstock_tuning.jpg/320px-Guitar_headstock_tuning.jpg"},
                       {"kind":"image","title":"Trimming","url":"https://cdn.example.com/original/trim.jpg","sourceUrl":"https://guitars.example/restringing","thumbnailUrl":"https://imgs.search.brave.com/trim-thumb.jpg"}]},
             {"rank":2,"link":"https://strings.example/guide","title":"String gauges explained","snippet":"","hostname":"strings.example"}]
            """#
        let messages: [[String: Any]] = [
            ["id": "ib4s", "runId": "ib4s", "role": "user", "content": "How do I restring my acoustic guitar?", "timestamp": 1000],
            [
                "id": "ib4sa", "runId": "ib4s", "role": "assistant",
                "content": [["type": "toolCall", "id": "k40", "name": "web_search", "arguments": ["query": "how to restring an acoustic guitar"]]],
                "stopReason": "toolUse", "timestamp": 1100,
            ],
            [
                "id": "ib4st", "runId": "ib4s", "role": "toolResult", "toolCallId": "k40", "toolName": "web_search",
                "content": [["type": "text", "text": "ok"]], "details": (try? JSONSerialization.jsonObject(with: Data(details.utf8))) ?? [],
                "isError": false, "timestamp": 1200,
            ],
            [
                "id": "ib4sb", "runId": "ib4s", "role": "assistant",
                "content": [["type": "text", "text": "Four steps, one string at a time so the neck's tension never drops\u{3010}1-source\u{3011}:\n\n```actovia-steps\n\(stepsSource)\n```"]],
                "stopReason": "stop", "timestamp": 1500,
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
