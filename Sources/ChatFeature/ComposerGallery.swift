#if DEBUG
import Foundation
import Models
import SwiftUI
import UIKit

/// `-MessageGallery -MessageGalleryComposer <state>`: the composer's `+` pieces over the message gallery, for
/// screenshots — `empty`, `pictures` (three), `preparing` (three, two more on their way), `full` (ten, Reasoning on),
/// `reasoning`, `research`, `mcp` (the sheet); voice input's `mic` (the empty composer's button), `recording` (the
/// meter, 0:12 in) and `transcribing`; `typed` (a line of text, the pill) and `multiline` (text that wrapped: the
/// field over the buttons' row).
enum ComposerGalleryState: String {
    case empty, pictures, preparing, full, reasoning, research, mcp, mic, recording, transcribing, typed, multiline

    static var launch: ComposerGalleryState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-MessageGalleryComposer"), index + 1 < arguments.count else {
            return nil
        }
        return ComposerGalleryState(rawValue: arguments[index + 1])
    }
}

/// The real composer pieces around a stand-in field, laid out as `ChatDetailView.composer` lays them out.
struct ComposerGalleryBar: View {
    let state: ComposerGalleryState

    @State private var tools = ComposerTools()
    @State private var attachments = ComposerAttachments()
    @State private var showsMcpTools = false
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.toneAccent) private var toneAccent
    @Environment(\.toneInk) private var toneInk
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ComposerPictureStrip(pictures: attachments.pictures, preparing: state == .preparing ? 2 : 0) {
                    attachments.remove($0)
                }
            }
            if tools.isActive {
                ComposerToolPills(tools: tools)
            }
            ComposerRowLayout(oneLineHeight: lineHeight) {
                ComposerToolsButton(tools: tools, attachments: attachments) { _ in }
                    .padding(.leading, -10)
                    .composerRole(.leading)
                Group {
                    switch state {
                    case .recording:
                        RecordingMeter(since: recordingSince) { 0.55 }
                    case .typed:
                        Text(verbatim: "Show me a counter in SwiftUI")
                    case .multiline:
                        Text(verbatim: Self.wrappedText)
                    default:
                        Text("ios:chat.composer.placeholder")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .composerRole(.field)
                Button {} label: {
                    TurnButtonLabel(
                        state: turnState,
                        glyph: TurnButtonLabel.glyph(turnState, scheme: colorScheme, accentGlyph: accentGlyph))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(TurnButtonLabel.fill(turnState, scheme: colorScheme, toneFill: toneAccent, toneInk: toneInk))
                .composerRole(.trailing)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        // As the chat screen: what tints is the tone's ink.
        .tint(toneInk)
        .task { prepare() }
        .sheet(isPresented: $showsMcpTools) { McpToolsSheet(groups: tools.mcpGroups) }
    }

    /// The button as the chat screen would draw it: the other states have pictures or a choice, so they send.
    private var turnState: TurnButtonState {
        switch state {
        case .mic, .empty: .mic
        case .recording: .recording
        case .transcribing: .transcribing
        default: .send
        }
    }

    private let recordingSince = Date.now.addingTimeInterval(-12)

    /// Long enough to wrap beside the buttons on every phone, and to a second line on the wide row.
    private static let wrappedText =
        "Write me a SwiftUI counter whose button grows a little when tapped and settles back with a spring"

    private func prepare() {
        tools.adopt(reasoningLevels: ["off", "low", "medium", "high", "xhigh"])
        if let mcp = Self.mcpTools { tools.adopt(mcpTools: mcp) }
        let colors: [UIColor] = [
            .systemOrange, .systemIndigo, .systemPink, .systemGreen, .systemYellow, .systemRed, .systemTeal,
            .systemBlue, .systemPurple, .systemBrown,
        ]
        switch state {
        case .empty, .mic, .recording, .transcribing, .typed, .multiline:
            break
        case .pictures, .preparing:
            attachments.append(Self.pictures(Array(colors.prefix(3))))
        case .full:
            attachments.append(Self.pictures(colors))
            tools.setEffort(.high)
        case .reasoning:
            tools.setEffort(.high)
        case .research:
            tools.setDeepResearch(true)
        case .mcp:
            showsMcpTools = true
        }
    }

    /// Flat pictures, portrait and landscape by turns, as the desktop stores them.
    private static func pictures(_ colors: [UIColor]) -> [ComposerPicture] {
        colors.enumerated().map { index, color in
            let (width, height): (CGFloat, CGFloat) = index.isMultiple(of: 2) ? (300, 400) : (400, 300)
            return ComposerPicture(
                mimeType: "image/png", dataURL: MessageGalleryFixtures.picture(color, width: width, height: height),
                pixelWidth: Int(width), pixelHeight: Int(height))
        }
    }

    private static let mcpTools: McpToolsResponse? = {
        let json = #"""
            {"tools":[{"mcpServerName":"filesystem","tools":[{"name":"read_file","description":"Reads a file **as text**. Paths are relative to the allowed folders."},{"name":"list_directory","description":"Lists a folder's entries:\n- files\n- folders"}]},
                      {"mcpServerName":"github","tools":[{"name":"search_issues","description":"Searches issues and pull requests."},{"name":"get_me","description":""}]}]}
            """#
        return try? JSONDecoder().decode(McpToolsResponse.self, from: Data(json.utf8))
    }()
}
#endif
