import SwiftUI
import UIKit

/// What a tapped `entity:` link opens: Wikipedia's summary of the article — its picture, title, one-line description
/// and the first paragraph (at most 600 characters), with a link to read on — or "nothing found" / "could not reach".
/// A sheet at medium height, as the spec asks; the summary is fetched when the sheet opens, never when the link is
/// drawn.
struct EntitySheet: View {
    let title: String
    let loader: EntityLoader?

    private enum Phase: Equatable {
        case loading
        case found(EntitySummary)
        case nothing(String)
        case failed
    }

    /// The most of an extract the sheet shows; "Read more" has the rest.
    private static let extractMax = 600

    @State private var phase = Phase.loading
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CardStyle.inset)
            }
            .navigationTitle(Text(verbatim: shownTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: title) { await load() }
    }

    private var shownTitle: String {
        if case .found(let summary) = phase { return summary.title }
        return title.replacingOccurrences(of: "_", with: " ")
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            Text("ios:chat.block.entityLoading").foregroundStyle(.secondary)
        case .failed:
            Text("ios:chat.block.entityFailed").foregroundStyle(.secondary)
        case .nothing:
            Text("ios:chat.block.entityNothing").foregroundStyle(.secondary)
        case .found(let summary):
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if let thumbnail = summary.thumbnail, let url = URL(string: thumbnail.source) {
                        EntityPicture(url: url)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: summary.title).font(.headline)
                        if let description = summary.description, !description.isEmpty {
                            Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if let extract = summary.extract {
                    Text(verbatim: Self.shortened(extract))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let page = summary.url.flatMap(URL.init(string:)) {
                    Button {
                        openURL(page)
                    } label: {
                        Label("ios:chat.block.readMore", systemImage: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    /// The first 600 characters, an ellipsis after a cut.
    static func shortened(_ extract: String) -> String {
        extract.count > extractMax ? String(extract.prefix(extractMax)) + "\u{2026}" : extract
    }

    private func load() async {
        phase = .loading
        guard let loader else {
            phase = .failed
            return
        }
        do {
            let summary = try await loader.summary(for: title, lang: EntityLoader.wikipediaLang(for: locale))
            phase = summary.extract == nil ? .nothing(summary.title) : .found(summary)
        } catch {
            phase = .failed
        }
    }
}

/// Wikipedia's thumbnail of the article — chosen by the route from the article, not written by the model, so it
/// loads on sight, through the search media loader as the gallery's thumbnails do.
private struct EntityPicture: View {
    let url: URL
    @State private var image: UIImage?
    @Environment(\.searchMediaLoader) private var loader

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.fill.quaternary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(CardStyle.innerShape)
        .accessibilityHidden(true)
        .task(id: url) {
            // Two steps, not `??`: its right side is an autoclosure, which cannot await.
            if let cached = loader.cached(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap) {
                image = cached
            } else {
                image = try? await loader.load(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap)
            }
        }
    }
}
