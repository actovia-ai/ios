import Foundation
import Models
import NetworkingKit
import SwiftUI

struct GroupArchiveView: View {
    let entries: [GroupArchiveEntry]
    let conversationId: String
    let api: PhilharmonicAPI
    @Environment(\.dismiss) private var dismiss
    @State private var downloads: [String: URL] = [:]
    @State private var loading: Set<String> = []
    @State private var error: String?

    private var unique: [GroupArchiveEntry] {
        var seen = Set<String>()
        return entries.reversed().filter { seen.insert($0.path).inserted }
    }

    var body: some View {
        NavigationStack {
            List(unique) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    if entry.directory { Label(entry.title, systemImage: "folder") }
                    else { Label(entry.title, systemImage: "doc.text") }
                    Text(verbatim: entry.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let url = downloads[entry.path] {
                        ShareLink(item: url)
                    } else {
                        Button {
                            loading.insert(entry.path)
                            Task {
                                defer { loading.remove(entry.path) }
                                do {
                                    let data = try await api.archiveFile(conversationId: conversationId, path: entry.path)
                                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                    var name = URL(fileURLWithPath: entry.path).lastPathComponent
                                    if entry.directory { name += ".zip" }
                                    let url = folder.appendingPathComponent(name)
                                    try data.write(to: url, options: .atomic)
                                    downloads[entry.path] = url
                                } catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            if loading.contains(entry.path) { ProgressView() }
                            else { Label("common:attachment.download", systemImage: "arrow.down.circle") }
                        }
                        .disabled(loading.contains(entry.path))
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if unique.isEmpty {
                    ContentUnavailableView {
                        Label("philharmonic:chat.archive.emptyTitle", systemImage: "archivebox")
                    } description: { Text("philharmonic:chat.archive.emptyDescription") }
                }
            }
            .navigationTitle(Text("philharmonic:chat.resourcesPanel.finalOutput"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common:action.close") { dismiss() } } }
            .alert(Text("common:clipboard.genericError"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("ios:app.alert.ok") { error = nil } } message: { Text(verbatim: error ?? "") }
        }
    }
}
